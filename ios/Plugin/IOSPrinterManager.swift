import Foundation
import CoreBluetooth
import adapter
import appleble

final class IOSPrinterManager: NSObject {
    private let printer = AppleBle()
    private let mapper = IOSStatusMapper()

    private var discoveredPeripherals: [String: CBPeripheral] = [:]
    private var discoveredRSSI: [String: NSNumber] = [:]
    private var discoveryPrefixes: [String] = []
    private var discoverySemaphore: DispatchSemaphore?
    private var connectSemaphore: DispatchSemaphore?
    private var connectErrorMessage: String?
    private var currentPeripheral: CBPeripheral?
    private(set) var connected = false
    private(set) var currentDeviceId: String?
    private var lastStatusCode: Int?
    private var lastMessage = "disconnected"
    private var lastRawMessage: String?

    override init() {
        super.init()
        printer.delegate = self
    }

    func discoverDevices(namePrefixes: [String], timeoutMs: Double) -> [[String: Any]] {
        discoveryPrefixes = namePrefixes
        discoveredPeripherals.removeAll()
        discoveredRSSI.removeAll()

        let semaphore = DispatchSemaphore(value: 0)
        discoverySemaphore = semaphore
        printer.startScanPrinters()

        let timeoutSeconds = max(timeoutMs, 500) / 1000
        DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) { [weak self] in
            self?.printer.stopScanPrinters()
            self?.discoverySemaphore?.signal()
        }
        _ = semaphore.wait(timeout: .now() + timeoutSeconds + 1)

        return discoveredPeripherals.keys.sorted().compactMap { deviceId in
            guard let peripheral = discoveredPeripherals[deviceId] else {
                return nil
            }

            var item: [String: Any] = [
                "id": deviceId,
                "name": peripheral.name ?? "Unknown BLE Printer",
                "transport": "ble"
            ]

            if let rssi = discoveredRSSI[deviceId] {
                item["rssi"] = rssi.intValue
            }

            return item
        }
    }

    func connect(deviceId: String) throws {
        guard let peripheral = discoveredPeripherals[deviceId] ?? currentPeripheral, peripheral.identifier.uuidString == deviceId else {
            throw NSError(
                domain: "LabelPrinter",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "printer device not found: \(deviceId)"]
            )
        }

        connectErrorMessage = nil
        let semaphore = DispatchSemaphore(value: 0)
        connectSemaphore = semaphore
        printer.connect(peripheral)

        let waitResult = semaphore.wait(timeout: .now() + 10)
        if waitResult == .timedOut {
            throw NSError(
                domain: "LabelPrinter",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "printer connect timeout"]
            )
        }

        guard connected else {
            throw NSError(
                domain: "LabelPrinter",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: connectErrorMessage ?? "printer connect failed"]
            )
        }

        currentPeripheral = peripheral
        currentDeviceId = deviceId
        lastMessage = "ready"
    }

    func disconnect() {
        printer.disconnect()
        connected = false
        currentPeripheral = nil
        currentDeviceId = nil
        lastStatusCode = nil
        lastRawMessage = nil
        lastMessage = "disconnected"
    }

    func getConnectionState() -> [String: Any] {
        return ["state": connected ? "connected" : "disconnected"]
    }

    func getStatus() -> [String: Any] {
        return mapper.toPluginStatus(
            connected: connected,
            statusCode: lastStatusCode,
            message: lastMessage,
            raw: lastRawMessage
        )
    }

    func print(payload: String, copies: Int) throws {
        if !connected {
            throw NSError(
                domain: "LabelPrinter",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "printer is not connected"]
            )
        }
        if payload.isEmpty || copies < 1 {
            throw NSError(
                domain: "LabelPrinter",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "invalid print payload"]
            )
        }
        guard let binary = payload
            .replacingOccurrences(of: "\r\n", with: "\n")
            .repeatString(max(copies, 1))
            .data(using: .utf8) else {
            throw NSError(
                domain: "LabelPrinter",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "unable to encode print payload"]
            )
        }

        printer.write(binary)
    }

    private func shouldKeep(peripheral: CBPeripheral) -> Bool {
        guard let name = peripheral.name, !name.isEmpty else {
            return false
        }
        guard !discoveryPrefixes.isEmpty else {
            return true
        }
        return discoveryPrefixes.contains { name.hasPrefix($0) }
    }
}

extension IOSPrinterManager: AppleBleDelegate {
    func bleDataReceived(_ revData: Data) {
        lastRawMessage = String(data: revData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let lastRawMessage, !lastRawMessage.isEmpty {
            lastMessage = lastRawMessage
        }
    }

    func bleDidDiscoverDevies(_ peripheral: CBPeripheral, rssi RSSI: NSNumber?) {
        guard shouldKeep(peripheral: peripheral) else {
            return
        }
        let deviceId = peripheral.identifier.uuidString
        discoveredPeripherals[deviceId] = peripheral
        if let RSSI {
            discoveredRSSI[deviceId] = RSSI
        }
    }

    func bleDidConnect(_ peripheral: CBPeripheral) {
        connected = true
        currentPeripheral = peripheral
        currentDeviceId = peripheral.identifier.uuidString
        lastMessage = "ready"
        connectSemaphore?.signal()
    }

    func bleDidFail(toConnect peripheral: CBPeripheral, error: (any Error)?) {
        connected = false
        connectErrorMessage = error?.localizedDescription ?? "printer connect failed"
        connectSemaphore?.signal()
    }

    func bleDidDisconnectPeripheral(_ peripheral: CBPeripheral, error: (any Error)?) {
        connected = false
        currentPeripheral = nil
        currentDeviceId = nil
        lastMessage = "disconnected"
        if let error {
            connectErrorMessage = error.localizedDescription
        }
        connectSemaphore?.signal()
    }

    func bleDidFinishPrint(_ result: printResult) {
        switch Int(result.rawValue) {
        case 0:
            lastMessage = "print success"
        case 1:
            lastMessage = "print failed"
        default:
            break
        }
    }

    func blePrinterStatus(_ status: printStatus) {
        lastStatusCode = Int(status.rawValue)
        lastMessage = mapper.message(for: Int(status.rawValue))
    }
}

private extension String {
    func repeatString(_ count: Int) -> String {
        guard count > 1 else {
            return self
        }
        return String(repeating: self, count: count)
    }
}
