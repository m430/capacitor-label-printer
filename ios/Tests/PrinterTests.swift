import Foundation
import CoreBluetooth
import Capacitor

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

func pump(_ seconds: TimeInterval = 0.01) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

final class Fixture {
    let manager = IOSPrinterManager(operationTimeout: 0.08, statusTimeout: 0.015)
    let central: CBCentralManager
    let peripheral = CBPeripheral()
    let writer: CBCharacteristic
    let reader = CBCharacteristic("FFF1", .notify)
    var connectionResults: [Bool] = []

    init(connect: Bool = true, properties: CBCharacteristicProperties = .write) {
        CBManager.authorization = .allowedAlways
        var scanDone = false
        manager.discoverDevices(namePrefixes: ["QR"], timeoutMs: 1) { result in
            if case .success(let devices) = result { expect(devices.count == 1, "discover one printer") }
            else { expect(false, "discovery succeeds") }
            scanDone = true
        }
        central = CBCentralManager.latest!
        writer = CBCharacteristic("FFF2", properties)
        peripheral.services = [CBService("FFF0", [writer, reader])]
        central.update(.poweredOn)
        central.discover(peripheral)
        pump()
        expect(scanDone, "scan resolves after timeout")
        manager.connect(deviceId: peripheral.identifier.uuidString) { [weak self] error in
            self?.connectionResults.append(error == nil)
        }
        if connect {
            central.connected(peripheral)
            expect(connectionResults.isEmpty, "connection does not resolve before characteristics")
            peripheral.discoverServicesAndCharacteristics()
            if properties.contains(.write) {
                expect(connectionResults.isEmpty, "connection waits for notification subscription")
                peripheral.notifyReady(reader)
                expect(connectionResults == [true], "ready connection resolves once")
            }
        }
    }

    func printTspl() {
        var completed = false
        manager.print(payload: "CLS\n", language: "tspl", copies: 1) { error in
            expect(error == nil, "TSPL write succeeds"); completed = true
        }
        peripheral.acknowledge(writer)
        expect(completed, "TSPL acknowledged")
    }

    func close() {
        manager.disconnect { _ in }
        central.disconnected(peripheral)
    }
}

@main
struct PrinterTests {
    static func main() {
        let cases: [(String, () -> Void)] = [
            ("bridge", bridge), ("permission", permission), ("scan-readiness", scanReadiness),
            ("powered-off", poweredOff), ("raw-bytes", rawBytes), ("cpcl-bytes", cpclBytes),
            ("tspl-lines", tsplLines), ("write-error", writeError), ("write-timeout", writeTimeout),
            ("no-response-only", noResponseOnly), ("unknown-language", unknownLanguage),
            ("status-fragments", statusFragments), ("status-timeout", statusTimeout),
            ("connect-timeout", connectTimeout), ("disconnect", disconnect),
            ("disconnect-retry-timeout", disconnectRetryTimeout), ("power-cycle", powerCycle),
            ("vendor-characteristics", vendorCharacteristics), ("busy-query", busyQuery),
            ("switch-cancel", switchCancel), ("scan-reentry", scanReentry),
            ("unnamed-hidden", unnamedHidden),
            ("generic-characteristics", genericCharacteristics),
            ("session-reset", sessionReset), ("invalid-input", invalidInput)
        ]
        for (name, test) in cases where CommandLine.arguments.count == 1 || CommandLine.arguments[1] == name {
            test()
            print("PASS: \(name)")
        }
    }

    static func bridge() {
        CBCentralManager.latest = nil
        let plugin: CAPPlugin = LabelPrinterPlugin()
        expect(CBCentralManager.latest == nil, "plugin loading must not prompt for Bluetooth")
        guard let bridge = plugin as? CAPBridgedPlugin else { expect(false, "Capacitor bridge conformance"); return }
        expect(bridge.identifier == "LabelPrinterPlugin" && bridge.jsName == "LabelPrinter", "bridge names match JS")
        let expected = ["isSupported", "checkPermissions", "ensurePermissions", "discoverDevices", "connect",
                        "disconnect", "getConnectionState", "print", "getStatus", "openAppSettings"]
        expect(Set(bridge.pluginMethods.map { $0.name }) == Set(expected), "all ten API methods exported")
        for method in bridge.pluginMethods {
            expect(method.returnType == CAPPluginReturnPromise, "promise bridge method")
            expect(plugin.responds(to: NSSelectorFromString(method.name + ":")), "actual Objective-C selector exists: \(method.name)")
        }
    }

    static func permission() {
        CBManager.authorization = .notDetermined
        let plugin = LabelPrinterPlugin()
        let check = CAPPluginCall()
        plugin.checkPermissions(check)
        expect(check.result?["granted"] as? Bool == false, "checkPermissions is truthful")
        let first = CAPPluginCall(), second = CAPPluginCall()
        plugin.ensurePermissions(first)
        plugin.ensurePermissions(second)
        expect(first.result == nil && second.result == nil, "ensurePermissions waits for actual authorization")
        CBManager.authorization = .denied
        CBCentralManager.latest!.update(.unauthorized)
        expect(first.result?["granted"] as? Bool == false, "denial not reported granted")
        expect(second.resolutions == 1 && first.resolutions == 1, "all permission calls settle once")
        expect(first.result?["shouldOpenSettings"] as? Bool == true, "denial offers settings")
        CBManager.authorization = .allowedAlways
    }

    static func scanReadiness() {
        CBManager.authorization = .notDetermined
        let manager = IOSPrinterManager(operationTimeout: 0.1)
        var result: Result<[[String: Any]], Error>?
        manager.discoverDevices(namePrefixes: ["QR"], timeoutMs: 1) { result = $0 }
        let central = CBCentralManager.latest!
        central.update(.poweredOn)
        pump()
        expect(!central.isScanning && result == nil, "scan timer does not consume authorization wait")
        CBManager.authorization = .allowedAlways
        central.update(.poweredOn)
        let named = CBPeripheral(); named.name = nil
        central.discover(named, advertisedName: "QR-Advertised")
        let other = CBPeripheral(); other.name = "Other"
        central.discover(other)
        pump()
        if case .success(let devices) = result {
            expect(devices.count == 1 && devices[0]["name"] as? String == "QR-Advertised", "filter advertised printer names")
        } else { expect(false, "scan succeeds after authorization") }
    }

    static func poweredOff() {
        let manager = IOSPrinterManager()
        var failed = false
        manager.discoverDevices(namePrefixes: [], timeoutMs: 1) { result in
            if case .failure = result { failed = true }
        }
        CBCentralManager.latest!.update(.poweredOff)
        expect(failed, "powered-off scan rejects instead of empty success")
    }

    static func checkBytes(language: String) {
        let f = Fixture()
        let bytes = Data(Array(repeating: Array(UInt8.min...UInt8.max), count: 5).flatMap { $0 } + [13, 10, 0, 255])
        let payload = String(data: bytes, encoding: .isoLatin1)!
        var results: [Bool] = []
        f.manager.print(payload: payload, language: language, copies: 2) { results.append($0 == nil) }
        expect(results.isEmpty && f.peripheral.writes.count == 1, "print waits for first BLE acknowledgement")
        var acknowledgements = 0
        while results.isEmpty && acknowledgements < 1000 {
            let count = f.peripheral.writes.count
            expect(count == acknowledgements + 1, "one outstanding chunk only")
            f.peripheral.acknowledge(f.writer)
            acknowledgements += 1
        }
        expect(results == [true], "print resolves exactly once after final acknowledgement")
        let actual = f.peripheral.writes.reduce(into: Data()) { $0.append($1.0) }
        expect(actual == bytes + bytes, "\(language) preserves all bytes, CRLF, copies and chunk boundaries")
        expect(f.peripheral.writes.allSatisfy { $0.0.count <= 23 && $0.2 == .withResponse }, "negotiated BLE chunk length and acknowledged mode")
        f.close()
    }

    static func rawBytes() { checkBytes(language: "raw") }
    static func cpclBytes() { checkBytes(language: "cpcl") }

    static func tsplLines() {
        let f = Fixture()
        var done = false
        f.manager.print(payload: " CLS\n\r\n PRINT 1,1 \r", language: "TSPL", copies: 2) { error in
            expect(error == nil, "TSPL success"); done = true
        }
        while !done { f.peripheral.acknowledge(f.writer) }
        let actual = f.peripheral.writes.reduce(into: Data()) { $0.append($1.0) }
        expect(actual == Data("CLS\r\nPRINT 1,1\r\nCLS\r\nPRINT 1,1\r\n".utf8), "TSPL line normalization is separate from raw")
        f.close()
    }

    static func writeError() {
        let f = Fixture()
        var failed = false
        f.manager.print(payload: "test", language: "raw", copies: 1) { failed = $0 != nil }
        f.peripheral.acknowledge(f.writer, error: NSError(domain: "BLE", code: 1))
        expect(failed && f.central.cancellations.count == 1, "write failure rejects and cancels connection")
        f.close()
    }

    static func writeTimeout() {
        let f = Fixture()
        var results: [Bool] = []
        f.manager.print(payload: "test", language: "raw", copies: 1) { results.append($0 == nil) }
        pump(0.1)
        expect(results == [false], "unacknowledged print times out")
        f.peripheral.acknowledge(f.writer)
        expect(results == [false], "late acknowledgement cannot resolve a failed job")
        f.close()
    }

    static func noResponseOnly() {
        let f = Fixture(properties: .writeWithoutResponse)
        expect(f.connectionResults == [false], "writeWithoutResponse-only printers are rejected explicitly")
        f.close()
    }

    static func unknownLanguage() {
        let f = Fixture()
        var result: [String: Any]?
        f.manager.getStatus { result = $0 }
        expect(f.peripheral.writes.isEmpty, "unknown language never sends READSTA")
        expect(result?["ready"] == nil, "connected is not proof of readiness")
        var done = false
        f.manager.print(payload: "CPCL\r\n", language: "cpcl", copies: 1) { _ in done = true }
        f.peripheral.acknowledge(f.writer)
        expect(done, "CPCL printed")
        let count = f.peripheral.writes.count
        f.manager.getStatus { result = $0 }
        expect(f.peripheral.writes.count == count, "CPCL never sends TSPL status commands")
        f.close()
    }

    static func statusFragments() {
        let f = Fixture()
        f.printTspl()
        var result: [String: Any]?
        f.peripheral.onWrite = { _ in f.peripheral.receive(Data("RE".utf8), on: f.reader) }
        f.manager.getStatus { result = $0 }
        f.peripheral.onWrite = nil
        expect(f.peripheral.writes.last?.0 == Data("READSTA \r\n".utf8), "vendor query command preserved")
        f.peripheral.receive(Data("ADY\r\n".utf8), on: f.reader)
        expect(result == nil, "query response still waits for write acknowledgement")
        f.peripheral.acknowledge(f.writer)
        let raw = result?["raw"] as? [String: Any]
        expect(raw?["data"] as? String == "READY\r\n", "capture fast reply and assemble notification fragments")
        expect(raw?["correlated"] as? Bool == false, "unidentified notifications cannot be claimed as query responses")
        expect(result?["ready"] == nil, "unverified response does not invent readiness")
        f.close()
    }

    static func statusTimeout() {
        let f = Fixture()
        f.printTspl()
        var completions = 0
        f.manager.getStatus { _ in completions += 1 }
        f.peripheral.acknowledge(f.writer)
        pump(0.03)
        expect(completions == 1, "query timeout settles once")
        let count = f.peripheral.writes.count
        f.manager.getStatus { _ in completions += 1 }
        f.peripheral.receive(Data("LATE\r\n".utf8), on: f.reader)
        expect(f.peripheral.writes.count == count && completions == 2, "timed-out session cannot misattribute late replies")
        f.close()
    }

    static func connectTimeout() {
        let f = Fixture(connect: false)
        pump(0.1)
        expect(f.connectionResults == [false] && f.central.cancellations.count == 1, "connect timeout cancels native request")
        f.central.connected(f.peripheral)
        expect(f.manager.getConnectionState()["state"] as? String == "disconnected", "late connection does not resurrect session")
        var retryFailed = false
        f.manager.connect(deviceId: f.peripheral.identifier.uuidString) { retryFailed = $0 != nil }
        expect(retryFailed, "cannot reuse peripheral until cancellation finishes")
        f.close()
    }

    static func disconnect() {
        let f = Fixture()
        var printed: Bool?
        f.manager.print(payload: "test", language: "raw", copies: 1) { printed = $0 == nil }
        var disconnected = false
        f.manager.disconnect { error in expect(error == nil, "disconnect succeeds"); disconnected = true }
        expect(printed == false && !disconnected, "disconnect cancels write but waits for native callback")
        f.central.disconnected(f.peripheral)
        expect(disconnected, "disconnect resolves after native disconnect")
    }

    static func disconnectRetryTimeout() {
        let f = Fixture()
        var failures = 0
        f.manager.disconnect { if $0 != nil { failures += 1 } }
        pump(0.1)
        expect(failures == 1, "first disconnect times out")
        f.manager.disconnect { if $0 != nil { failures += 1 } }
        pump(0.1)
        expect(failures == 2, "repeated disconnect must not hang after a previous timeout")
        f.close()
    }

    static func powerCycle() {
        let f = Fixture()
        f.central.update(.poweredOff)
        f.central.update(.poweredOn)
        var rejected = false
        f.manager.connect(deviceId: f.peripheral.identifier.uuidString) { rejected = $0 != nil }
        expect(rejected, "power cycle discards invalid peripheral references and requires rediscovery")
        f.close()
    }

    static func vendorCharacteristics() {
        let f = Fixture(connect: false)
        let writer = CBCharacteristic("49535343-8841-43F4-A8D4-ECBE34729BB3", .write)
        let reader = CBCharacteristic("49535343-1E4D-4BD9-BA61-23C647249616", .notify)
        f.peripheral.services!.append(CBService("49535343-FE7D-4AE5-8FA9-9FAFD205E455", [reader, writer]))
        f.central.connected(f.peripheral)
        f.peripheral.discoverServicesAndCharacteristics()
        expect(f.peripheral.notificationRequests == [reader], "known vendor notify UUID takes precedence")
        f.peripheral.notifyReady(reader)
        var done = false
        f.manager.print(payload: "test", language: "raw", copies: 1) { _ in done = true }
        expect(f.peripheral.writes.last?.1 === writer, "known vendor write UUID takes precedence")
        f.peripheral.acknowledge(writer)
        expect(done, "vendor characteristic acknowledgement completes print")
        f.close()
    }

    static func busyQuery() {
        let f = Fixture()
        f.printTspl()
        f.manager.getStatus { _ in }
        var rejected = false
        f.manager.print(payload: "test", language: "raw", copies: 1) { rejected = $0 != nil }
        expect(rejected, "print cannot overlap an active query")
        var busyStatus: [String: Any]?
        let count = f.peripheral.writes.count
        f.manager.getStatus { busyStatus = $0 }
        expect(busyStatus?["ready"] == nil && f.peripheral.writes.count == count, "concurrent status does not start another query")
        f.close()
    }

    static func switchCancel() {
        let f = Fixture()
        let next = CBPeripheral()
        f.manager.discoverDevices(namePrefixes: [], timeoutMs: 1) { _ in }
        f.central.discover(next)
        pump()
        var switchFailed = false
        f.manager.connect(deviceId: next.identifier.uuidString) { switchFailed = $0 != nil }
        var disconnected = false
        f.manager.disconnect { _ in disconnected = true }
        f.central.disconnected(f.peripheral)
        pump()
        expect(switchFailed && disconnected && f.central.connections.count == 1,
               "explicit disconnect cancels a queued printer switch")
    }

    static func scanReentry() {
        CBManager.authorization = .notDetermined
        let manager = IOSPrinterManager()
        var restarted = false
        manager.discoverDevices(namePrefixes: [], timeoutMs: 1) { result in
            if case .failure = result {
                manager.discoverDevices(namePrefixes: [], timeoutMs: 1) { result in
                    if case .success = result { restarted = true }
                }
            }
        }
        manager.disconnect { _ in }
        pump()
        CBManager.authorization = .allowedAlways
        CBCentralManager.latest!.update(.poweredOn)
        pump()
        expect(restarted, "scan restarted from cancelled completion must retain its own callback")
        expect(!CBCentralManager.latest!.isScanning, "no orphaned scan remains")
    }

    static func unnamedHidden() {
        CBManager.authorization = .allowedAlways
        let manager = IOSPrinterManager()
        var devices: [[String: Any]] = []
        manager.discoverDevices(namePrefixes: [], timeoutMs: 1) { result in
            if case .success(let found) = result { devices = found } else { expect(false, "scan succeeds") }
        }
        let central = CBCentralManager.latest!
        central.update(.poweredOn)
        let unnamed = CBPeripheral(); unnamed.name = nil
        central.discover(unnamed)
        let named = CBPeripheral(); named.name = "GT1-Test"
        central.discover(named)
        let advertised = CBPeripheral(); advertised.name = nil
        central.discover(advertised, advertisedName: "QR-Advertised")
        pump()
        expect(devices.count == 2, "advertisers without a name are hidden")
        expect(Set(devices.compactMap { $0["name"] as? String }) == Set(["GT1-Test", "QR-Advertised"]),
               "device names come from the peripheral, never invented")
    }

    static func genericCharacteristics() {
        let f = Fixture(connect: false)
        let configuration = CBCharacteristic("CONFIG-WRITE", .write)
        f.peripheral.services!.insert(CBService("CONFIG-SERVICE", [configuration]), at: 0)
        f.central.connected(f.peripheral)
        f.peripheral.discoverServicesAndCharacteristics()
        expect(f.peripheral.notificationRequests == [f.reader], "skip unrelated writable configuration services")
        f.peripheral.notifyReady(f.reader)
        f.manager.print(payload: "test", language: "raw", copies: 1) { _ in }
        expect(f.peripheral.writes.last?.1 === f.writer, "data goes to the bidirectional printer service")
        f.peripheral.acknowledge(f.writer)
        f.close()
    }

    static func sessionReset() {
        let f = Fixture()
        f.printTspl()
        f.close()
        f.manager.connect(deviceId: f.peripheral.identifier.uuidString) { expect($0 == nil, "reconnect succeeds") }
        f.central.connected(f.peripheral)
        f.peripheral.discoverServicesAndCharacteristics()
        f.peripheral.notifyReady(f.reader)
        let count = f.peripheral.writes.count
        f.manager.getStatus { expect($0["ready"] == nil, "new session has no stale status") }
        expect(f.peripheral.writes.count == count, "new session has no stale language")
        f.close()
    }

    static func invalidInput() {
        let f = Fixture()
        for (payload, language, copies) in [("", "raw", 1), ("test", "unknown", 1), ("test", "raw", 0), ("中文", "cpcl", 1)] {
            var failed = false
            f.manager.print(payload: payload, language: language, copies: copies) { failed = $0 != nil }
            expect(failed, "invalid payload fails before writing")
        }
        expect(f.peripheral.writes.isEmpty, "invalid input never reaches BLE")
        f.close()
    }
}
