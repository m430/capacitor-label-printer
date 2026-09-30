import Foundation
import CoreBluetooth

final class IOSPrinterManager: NSObject {
    private final class WriteJob {
        let data: Data
        let completion: (Error?) -> Void
        var offset = 0
        var chunkLength = 0
        var chunkCount = 0
        var timer: DispatchWorkItem?
        let startedAt = Date()

        init(data: Data, completion: @escaping (Error?) -> Void) {
            self.data = data
            self.completion = completion
        }
    }

    private final class StatusQuery {
        let completion: ([String: Any]) -> Void
        var data = Data()
        var writeConfirmed = false
        var responseComplete = false
        var timer: DispatchWorkItem?

        init(completion: @escaping ([String: Any]) -> Void) {
            self.completion = completion
        }
    }

    private let operationTimeout: TimeInterval
    private let statusTimeout: TimeInterval
    private let mapper = IOSStatusMapper()
    private var central: CBCentralManager?
    private var permissionCallbacks: [(CBManagerAuthorization) -> Void] = []
    private var readyCallback: ((Error?) -> Void)?
    private var readyTimer: DispatchWorkItem?
    private var scanCallback: ((Result<[[String: Any]], Error>) -> Void)?
    private var scanTimer: DispatchWorkItem?
    private var prefixes: [String] = []
    private var peripherals: [String: CBPeripheral] = [:]
    private var devices: [String: [String: Any]] = [:]
    private var currentPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var writeType: CBCharacteristicWriteType = .withResponse
    private var notifyCharacteristic: CBCharacteristic?
    private var pendingServices = Set<CBUUID>()
    private var connected = false
    private var disconnecting = false
    private var connectCallback: ((Error?) -> Void)?
    private var connectTimer: DispatchWorkItem?
    private var disconnectCallbacks: [(Error?) -> Void] = []
    private var disconnectTimer: DispatchWorkItem?
    private var writeJob: WriteJob?
    private var query: StatusQuery?
    private var activeLanguage: String?
    private var queryAllowed = true
    private var switchID: UUID?
    private var deliveringCallbacks = false

    init(operationTimeout: TimeInterval = 10, statusTimeout: TimeInterval = 1.5) {
        self.operationTimeout = operationTimeout
        self.statusTimeout = statusTimeout
        super.init()
    }

    func getAuthorization() -> CBManagerAuthorization {
        if #available(iOS 13.1, *) { return CBManager.authorization }
        let snapshot = { self.central?.authorization ?? .notDetermined }
        return Thread.isMainThread ? snapshot() : DispatchQueue.main.sync(execute: snapshot)
    }

    func ensurePermissions(completion: @escaping (CBManagerAuthorization) -> Void) {
        onMain {
            let authorization = self.getAuthorization()
            if authorization != .notDetermined {
                completion(authorization)
                return
            }
            self.permissionCallbacks.append(completion)
            self.createCentral()
        }
    }

    func discoverDevices(
        namePrefixes: [String], timeoutMs: Double,
        completion: @escaping (Result<[[String: Any]], Error>) -> Void
    ) {
        onMain {
            guard timeoutMs.isFinite, timeoutMs > 0, timeoutMs <= 60000 else {
                completion(.failure(self.error("scan timeout must be between 0 and 60000 ms")))
                return
            }
            guard !self.busy else {
                completion(.failure(self.error("printer is busy")))
                return
            }
            self.scanCallback = completion
            self.prefixes = namePrefixes
            self.devices.removeAll()
            self.peripherals.removeAll()
            self.whenReady { error in
                if let error {
                    self.finishScan(.failure(error))
                    return
                }
                self.central?.scanForPeripherals(withServices: nil, options: nil)
                self.scanTimer = self.after(timeoutMs / 1000) {
                    self.finishScan(.success(self.devices.keys.sorted().compactMap { self.devices[$0] }))
                }
            }
        }
    }

    func connect(deviceId: String, completion: @escaping (Error?) -> Void) {
        onMain {
            guard !self.busy else {
                completion(self.error("printer is busy"))
                return
            }
            if self.connected, self.currentPeripheral?.identifier.uuidString == deviceId {
                completion(nil)
                return
            }
            guard let peripheral = self.peripherals[deviceId] else {
                completion(self.error("printer device not found: \(deviceId), call discoverDevices first"))
                return
            }
            if self.currentPeripheral != nil {
                let id = UUID()
                self.switchID = id
                self.disconnectCallbacks.append { error in
                    self.onMain {
                        guard self.switchID == id else {
                            completion(self.error("printer switch cancelled"))
                            return
                        }
                        self.switchID = nil
                        if let error {
                            completion(error)
                        } else {
                            self.connect(deviceId: deviceId, completion: completion)
                        }
                    }
                }
                self.cancelSession(self.error("switching printer"))
                return
            }
            self.connectCallback = completion
            self.whenReady { error in
                if let error {
                    self.finishConnect(error)
                    return
                }
                self.currentPeripheral = peripheral
                self.activeLanguage = nil
                self.queryAllowed = true
                peripheral.delegate = self
                self.connectTimer = self.after(self.operationTimeout) {
                    self.cancelSession(self.error("printer connect timeout"))
                }
                self.central?.connect(peripheral, options: nil)
            }
        }
    }

    func disconnect(completion: @escaping (Error?) -> Void) {
        onMain {
            self.switchID = nil
            self.disconnectCallbacks.append(completion)
            self.cancelSession(self.error("printer operation cancelled"))
        }
    }

    func getConnectionState() -> [String: Any] {
        let snapshot = {
            ["state": self.connected ? "connected" : (self.connectCallback != nil ? "connecting" : "disconnected")]
        }
        return Thread.isMainThread ? snapshot() : DispatchQueue.main.sync(execute: snapshot)
    }

    func print(payload: String, language: String, copies: Int, completion: @escaping (Error?) -> Void) {
        onMain {
            guard self.connected else {
                completion(self.error("printer is not connected"))
                return
            }
            guard !self.busy else {
                completion(self.error("printer is busy"))
                return
            }
            let language = language.lowercased()
            guard ["tspl", "cpcl", "raw"].contains(language), copies > 0, copies <= 1000, !payload.isEmpty else {
                completion(self.error("invalid print payload, language or copies (1...1000)"))
                return
            }
            let text: String
            if language == "tspl" {
                let lines = payload.replacingOccurrences(of: "\r\n", with: "\n")
                    .replacingOccurrences(of: "\r", with: "\n")
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                guard !lines.isEmpty else {
                    completion(self.error("tspl payload does not contain any printable commands"))
                    return
                }
                text = lines.joined(separator: "\r\n") + "\r\n"
            } else {
                text = payload
            }
            guard let data = text.data(using: language == "tspl" ? .utf8 : .isoLatin1) else {
                completion(self.error("unable to encode print payload"))
                return
            }
            let repeated: Data
            if copies == 1 {
                repeated = data
            } else {
                var combined = Data()
                combined.reserveCapacity(data.count * copies)
                for _ in 0..<copies { combined.append(data) }
                repeated = combined
            }
            self.activeLanguage = language
            self.startWrite(repeated, completion: completion)
        }
    }

    func getStatus(completion: @escaping ([String: Any]) -> Void) {
        onMain {
            guard self.connected else {
                completion(self.status(message: "disconnected"))
                return
            }
            guard !self.busy, self.activeLanguage == "tspl", self.queryAllowed,
                  self.notifyCharacteristic?.isNotifying == true else {
                completion(self.status(message: "status unknown"))
                return
            }
            let query = StatusQuery(completion: completion)
            self.query = query
            self.startWrite(Data("READSTA \r\n".utf8)) { error in
                guard self.query === query else { return }
                if let error {
                    self.finishQuery(message: error.localizedDescription, invalidate: true)
                    return
                }
                query.writeConfirmed = true
                if query.responseComplete {
                    self.finishQuery(message: "unverified BLE notification")
                } else {
                    query.timer = self.after(self.statusTimeout) {
                        guard self.query === query else { return }
                        self.finishQuery(message: "status response timeout", invalidate: true)
                    }
                }
            }
        }
    }

    private var busy: Bool {
        scanCallback != nil || connectCallback != nil || readyCallback != nil ||
            writeJob != nil || query != nil || disconnecting || switchID != nil
    }

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread && !deliveringCallbacks { work() } else { DispatchQueue.main.async(execute: work) }
    }

    private func deliver(_ work: () -> Void) {
        let previous = deliveringCallbacks
        deliveringCallbacks = true
        defer { deliveringCallbacks = previous }
        work()
    }

    private func after(_ delay: TimeInterval, _ work: @escaping () -> Void) -> DispatchWorkItem {
        let item = DispatchWorkItem(block: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return item
    }

    private func error(_ message: String) -> NSError {
        NSError(domain: "LabelPrinter", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func createCentral() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        }
    }

    private func whenReady(_ completion: @escaping (Error?) -> Void) {
        readyCallback = completion
        readyTimer = after(operationTimeout) {
            self.finishReady(self.error("bluetooth readiness timeout"))
        }
        createCentral()
        resolveReadiness()
    }

    private func resolveReadiness() {
        let authorization = getAuthorization()
        if authorization != .notDetermined {
            let callbacks = permissionCallbacks
            permissionCallbacks.removeAll()
            deliver { callbacks.forEach { $0(authorization) } }
        }
        guard readyCallback != nil, let central else { return }
        if authorization == .denied || authorization == .restricted {
            finishReady(error("PERMISSION_DENIED"))
            return
        }
        guard authorization == .allowedAlways else { return }
        switch central.state {
        case .poweredOn: finishReady(nil)
        case .poweredOff: finishReady(error("bluetooth is powered off"))
        case .unsupported: finishReady(error("bluetooth is unsupported"))
        case .unauthorized: finishReady(error("PERMISSION_DENIED"))
        case .unknown, .resetting: break
        @unknown default: finishReady(error("bluetooth is unavailable"))
        }
    }

    private func finishReady(_ error: Error?) {
        readyTimer?.cancel()
        readyTimer = nil
        let callback = readyCallback
        readyCallback = nil
        deliver { callback?(error) }
    }

    private func finishScan(_ result: Result<[[String: Any]], Error>) {
        scanTimer?.cancel()
        scanTimer = nil
        central?.stopScan()
        let callback = scanCallback
        scanCallback = nil
        deliver { callback?(result) }
    }

    private func finishConnect(_ error: Error?) {
        connectTimer?.cancel()
        connectTimer = nil
        let callback = connectCallback
        connectCallback = nil
        deliver { callback?(error) }
    }

    private func startWrite(_ data: Data, completion: @escaping (Error?) -> Void) {
        writeJob = WriteJob(data: data, completion: completion)
        let limit = currentPeripheral?.maximumWriteValueLength(for: writeType) ?? 0
        NSLog("[LabelPrinter] print begin bytes=\(data.count) limit=\(limit) type=\(writeType == .withResponse ? "ack" : "noAck")")
        writeNextChunk()
    }

    private func writeNextChunk() {
        guard let job = writeJob, let peripheral = currentPeripheral,
              let characteristic = writeCharacteristic, connected else {
            finishWrite(error("printer is not connected"))
            return
        }
        guard peripheral.state == .connected else {
            cancelSession(error("printer connection lost during write"))
            return
        }
        if job.offset == job.data.count {
            finishWrite(nil)
            return
        }
        if writeType == .withResponse {
            writeWithResponseChunk(job: job, peripheral: peripheral, characteristic: characteristic)
        } else {
            pumpWithoutResponse(job: job, peripheral: peripheral, characteristic: characteristic)
        }
    }

    private func writeWithResponseChunk(
        job: WriteJob, peripheral: CBPeripheral, characteristic: CBCharacteristic
    ) {
        let limit = peripheral.maximumWriteValueLength(for: .withResponse)
        guard limit > 0 else {
            cancelSession(error("invalid BLE write length"))
            return
        }
        job.chunkLength = min(limit, job.data.count - job.offset)
        let chunk = job.data.subdata(in: job.offset..<(job.offset + job.chunkLength))
        job.chunkCount += 1
        job.timer = after(operationTimeout) {
            guard self.writeJob === job else { return }
            self.cancelSession(self.error("printer write acknowledgement timeout; delivery is uncertain"))
        }
        peripheral.writeValue(chunk, for: characteristic, type: .withResponse)
    }

    /// Streams chunks with unacknowledged writes and pauses only when the transmit buffer
    /// reports full; peripheralIsReady resumes the job. Each write is guarded by
    /// canSendWriteWithoutResponse because writing into a full buffer discards data.
    /// Completion additionally waits until the buffer is no longer saturated, so success
    /// means the link actually drained every submitted byte.
    private func pumpWithoutResponse(
        job: WriteJob, peripheral: CBPeripheral, characteristic: CBCharacteristic
    ) {
        let limit = peripheral.maximumWriteValueLength(for: .withoutResponse)
        guard limit > 0 else {
            cancelSession(error("invalid BLE write length"))
            return
        }
        while job.offset < job.data.count, peripheral.canSendWriteWithoutResponse {
            job.chunkLength = min(limit, job.data.count - job.offset)
            let chunk = job.data.subdata(in: job.offset..<(job.offset + job.chunkLength))
            job.offset += job.chunkLength
            job.chunkCount += 1
            peripheral.writeValue(chunk, for: characteristic, type: .withoutResponse)
        }
        if job.offset == job.data.count, peripheral.canSendWriteWithoutResponse {
            // Every byte reached CoreBluetooth and the transmit buffer is not saturated.
            finishWrite(nil)
            return
        }
        // Either unsubmitted bytes remain (buffer full) or the final bytes are still
        // draining through a saturated buffer. Wait for peripheralIsReady; guard the wait
        // so a silent stack cannot hang the print promise forever.
        job.timer?.cancel()
        job.timer = after(operationTimeout) {
            guard self.writeJob === job else { return }
            self.cancelSession(self.error("printer write stalled; delivery is uncertain"))
        }
    }

    private func finishWrite(_ error: Error?) {
        let job = writeJob
        writeJob = nil
        job?.timer?.cancel()
        if let job {
            let elapsed = Int(Date().timeIntervalSince(job.startedAt) * 1000)
            let status = error == nil ? "done" : "failed"
            NSLog("[LabelPrinter] print \(status) chunks=\(job.chunkCount) elapsed=\(elapsed)ms")
        }
        deliver { job?.completion(error) }
    }

    private func status(message: String, raw: Data? = nil) -> [String: Any] {
        var result = mapper.toPluginStatus(connected: connected, message: message, raw: raw)
        if connected, let peripheral = currentPeripheral {
            result["deviceId"] = peripheral.identifier.uuidString
            result["deviceName"] = peripheral.name
        }
        return result
    }

    private func finishQuery(message: String, invalidate: Bool = false) {
        guard let query else { return }
        self.query = nil
        query.timer?.cancel()
        // READSTA has no request ID; a timed-out reply must never satisfy a later query.
        if invalidate { queryAllowed = false }
        deliver { query.completion(status(message: message, raw: query.data)) }
    }

    private func cancelSession(_ reason: Error) {
        let alreadyDisconnecting = disconnecting
        disconnecting = currentPeripheral != nil
        connected = false
        activeLanguage = nil
        finishReady(reason)
        finishScan(.failure(reason))
        finishConnect(reason)
        finishWrite(reason)
        finishQuery(message: reason.localizedDescription, invalidate: true)
        guard let peripheral = currentPeripheral else {
            finishDisconnect(nil)
            return
        }
        if disconnectTimer == nil {
            disconnectTimer = after(operationTimeout) {
                self.disconnectTimer = nil
                let callbacks = self.disconnectCallbacks
                self.disconnectCallbacks.removeAll()
                self.deliver { callbacks.forEach { $0(self.error("printer disconnect timeout")) } }
            }
        }
        if !alreadyDisconnecting { central?.cancelPeripheralConnection(peripheral) }
    }

    private func finishDisconnect(_ error: Error?) {
        disconnectTimer?.cancel()
        disconnectTimer = nil
        currentPeripheral?.delegate = nil
        currentPeripheral = nil
        writeCharacteristic = nil
        writeType = .withResponse
        notifyCharacteristic = nil
        pendingServices.removeAll()
        connected = false
        disconnecting = false
        activeLanguage = nil
        queryAllowed = true
        let callbacks = disconnectCallbacks
        disconnectCallbacks.removeAll()
        deliver { callbacks.forEach { $0(error) } }
    }
}

extension IOSPrinterManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        resolveReadiness()
        if central.state != .poweredOn, central.state != .unknown {
            let reason = error("bluetooth became unavailable")
            peripherals.removeAll()
            devices.removeAll()
            cancelSession(reason)
            finishDisconnect(reason)
        }
    }

    func centralManager(
        _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any], rssi RSSI: NSNumber
    ) {
        guard scanCallback != nil, central.isScanning else { return }
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        guard !name.isEmpty else { return }
        guard prefixes.isEmpty || prefixes.contains(where: { name.hasPrefix($0) }) else { return }
        let id = peripheral.identifier.uuidString
        peripherals[id] = peripheral
        devices[id] = ["id": id, "name": name, "transport": "ble", "rssi": RSSI.intValue]
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral === currentPeripheral, connectCallback != nil, !disconnecting else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral === currentPeripheral else { return }
        let reason = error ?? self.error("printer connect failed")
        finishConnect(reason)
        finishDisconnect(disconnecting ? nil : reason)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral === currentPeripheral else { return }
        let wasDisconnecting = disconnecting
        let reason = error ?? self.error("printer disconnected")
        connected = false
        finishConnect(reason)
        finishWrite(reason)
        finishQuery(message: reason.localizedDescription, invalidate: true)
        finishDisconnect(wasDisconnecting ? nil : error)
    }
}

extension IOSPrinterManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === currentPeripheral, connectCallback != nil, !disconnecting else { return }
        if let error { cancelSession(error); return }
        guard let services = peripheral.services, !services.isEmpty else {
            cancelSession(self.error("printer has no BLE services"))
            return
        }
        pendingServices = Set(services.map { $0.uuid })
        for service in services { peripheral.discoverCharacteristics(nil, for: service) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral === currentPeripheral, connectCallback != nil, !disconnecting else { return }
        if let error { cancelSession(error); return }
        pendingServices.remove(service.uuid)
        guard pendingServices.isEmpty else { return }
        let services = peripheral.services ?? []
        let vendorService = CBUUID(string: "49535343-FE7D-4AE5-8FA9-9FAFD205E455")
        let vendorWrite = CBUUID(string: "49535343-8841-43F4-A8D4-ECBE34729BB3")
        let vendorNotify = CBUUID(string: "49535343-1E4D-4BD9-BA61-23C647249616")
        let preferred = services.first { $0.uuid == vendorService }
        let candidates = preferred.map { [$0] } ?? services
        let pairs: [(CBCharacteristic, CBCharacteristic)] = candidates.compactMap { candidate in
            let characteristics = candidate.characteristics ?? []
            let writers = characteristics.filter {
                ($0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse)) &&
                    (preferred == nil || $0.uuid == vendorWrite)
            }
            let readers = characteristics.filter {
                ($0.properties.contains(.notify) || $0.properties.contains(.indicate)) &&
                    (preferred == nil || $0.uuid == vendorNotify)
            }
            guard writers.count == 1, readers.count == 1 else { return nil }
            return (writers[0], readers[0])
        }
        guard pairs.count == 1, let pair = pairs.first else {
            cancelSession(self.error("printer requires an unambiguous BLE service with a write characteristic and notifications"))
            return
        }
        writeCharacteristic = pair.0
        writeType = pair.0.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        notifyCharacteristic = pair.1
        peripheral.setNotifyValue(true, for: pair.1)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === currentPeripheral, characteristic === notifyCharacteristic, !disconnecting else { return }
        if let error { cancelSession(error); return }
        guard characteristic.isNotifying else {
            cancelSession(self.error("printer notifications stopped"))
            return
        }
        if connectCallback != nil {
            connected = true
            finishConnect(nil)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === currentPeripheral, characteristic === writeCharacteristic,
              !disconnecting, let job = writeJob else { return }
        job.timer?.cancel()
        if let error { cancelSession(error); return }
        job.offset += job.chunkLength
        writeNextChunk()
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        onMain {
            guard peripheral === self.currentPeripheral, !self.disconnecting,
                  self.writeJob != nil, self.writeType == .withoutResponse else { return }
            guard peripheral.state == .connected else {
                self.cancelSession(self.error("printer connection lost during write"))
                return
            }
            self.writeNextChunk()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === currentPeripheral, characteristic === notifyCharacteristic,
              !disconnecting, let query else { return }
        if let error {
            finishQuery(message: error.localizedDescription, invalidate: true)
            return
        }
        guard let data = characteristic.value, !data.isEmpty else { return }
        guard query.data.count + data.count <= 4096 else {
            finishQuery(message: "status response too large", invalidate: true)
            return
        }
        query.data.append(data)
        query.responseComplete = query.data.suffix(2) == Data([13, 10]) || query.data.suffix(10) == Data("ENDRECEIVE".utf8)
        if query.responseComplete, query.writeConfirmed {
            finishQuery(message: "unverified BLE notification")
        }
    }
}
