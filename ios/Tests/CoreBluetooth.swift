import Foundation

public enum CBManagerAuthorization { case notDetermined, restricted, denied, allowedAlways }
public enum CBManagerState { case unknown, resetting, unsupported, unauthorized, poweredOff, poweredOn }
public enum CBPeripheralState { case disconnected, connecting, connected, disconnecting }
public enum CBCharacteristicWriteType { case withResponse, withoutResponse }
public let CBAdvertisementDataLocalNameKey = "localName"

public struct CBCharacteristicProperties: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let write = Self(rawValue: 8)
    public static let writeWithoutResponse = Self(rawValue: 4)
    public static let notify = Self(rawValue: 16)
    public static let indicate = Self(rawValue: 32)
}

public final class CBUUID: NSObject {
    public let uuidString: String
    public init(string: String) { uuidString = string.uppercased() }
    public override var hash: Int { uuidString.hashValue }
    public override func isEqual(_ object: Any?) -> Bool { (object as? CBUUID)?.uuidString == uuidString }
}

open class CBManager: NSObject {
    public static var authorization: CBManagerAuthorization = .allowedAlways
    public var authorization: CBManagerAuthorization { Self.authorization }
    public var state: CBManagerState = .unknown
}

public protocol CBCentralManagerDelegate: AnyObject {
    func centralManagerDidUpdateState(_ central: CBCentralManager)
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber)
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral)
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?)
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?)
}

public final class CBCentralManager: CBManager {
    public static var latest: CBCentralManager?
    public weak var delegate: CBCentralManagerDelegate?
    public var isScanning = false
    public var connections: [CBPeripheral] = []
    public var cancellations: [CBPeripheral] = []
    public init(delegate: CBCentralManagerDelegate?, queue: DispatchQueue?) {
        self.delegate = delegate
        super.init()
        Self.latest = self
    }
    public func scanForPeripherals(withServices: [CBUUID]?, options: [String: Any]?) { isScanning = true }
    public func stopScan() { isScanning = false }
    public func connect(_ peripheral: CBPeripheral, options: [String: Any]?) {
        connections.append(peripheral)
        peripheral.state = .connecting
    }
    public func cancelPeripheralConnection(_ peripheral: CBPeripheral) { cancellations.append(peripheral) }
    public func update(_ state: CBManagerState) {
        self.state = state
        delegate?.centralManagerDidUpdateState(self)
    }
    public func discover(_ peripheral: CBPeripheral, advertisedName: String? = nil) {
        delegate?.centralManager(self, didDiscover: peripheral,
            advertisementData: advertisedName.map { [CBAdvertisementDataLocalNameKey: $0] } ?? [:], rssi: -40)
    }
    public func connected(_ peripheral: CBPeripheral) {
        peripheral.state = .connected
        delegate?.centralManager(self, didConnect: peripheral)
    }
    public func disconnected(_ peripheral: CBPeripheral) {
        peripheral.state = .disconnected
        delegate?.centralManager(self, didDisconnectPeripheral: peripheral, error: nil)
    }
}

public final class CBService: NSObject {
    public let uuid: CBUUID
    public var characteristics: [CBCharacteristic]?
    public init(_ uuid: String, _ characteristics: [CBCharacteristic]) {
        self.uuid = CBUUID(string: uuid)
        self.characteristics = characteristics
    }
}

public final class CBCharacteristic: NSObject {
    public let uuid: CBUUID
    public let properties: CBCharacteristicProperties
    public var isNotifying = false
    public var value: Data?
    public init(_ uuid: String, _ properties: CBCharacteristicProperties) {
        self.uuid = CBUUID(string: uuid)
        self.properties = properties
    }
}

public protocol CBPeripheralDelegate: AnyObject {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?)
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral)
}

public final class CBPeripheral: NSObject {
    public let identifier = UUID()
    public var name: String? = "QR-Test"
    public var state: CBPeripheralState = .disconnected
    public weak var delegate: CBPeripheralDelegate?
    public var services: [CBService]?
    public var writeLimit = 23
    public var canSendWriteWithoutResponse = true
    public var writes: [(Data, CBCharacteristic, CBCharacteristicWriteType)] = []
    public var notificationRequests: [CBCharacteristic] = []
    public var onWrite: ((Data) -> Void)?
    public func discoverServices(_ serviceUUIDs: [CBUUID]?) {}
    public func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]?, for service: CBService) {}
    public func setNotifyValue(_ enabled: Bool, for characteristic: CBCharacteristic) { notificationRequests.append(characteristic) }
    public func maximumWriteValueLength(for type: CBCharacteristicWriteType) -> Int { writeLimit }
    public func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType) {
        writes.append((data, characteristic, type))
        onWrite?(data)
    }
    public func discoverServicesAndCharacteristics() {
        delegate?.peripheral(self, didDiscoverServices: nil)
        for service in services ?? [] {
            delegate?.peripheral(self, didDiscoverCharacteristicsFor: service, error: nil)
        }
    }
    public func notifyReady(_ characteristic: CBCharacteristic) {
        characteristic.isNotifying = true
        delegate?.peripheral(self, didUpdateNotificationStateFor: characteristic, error: nil)
    }
    public func acknowledge(_ characteristic: CBCharacteristic, error: Error? = nil) {
        delegate?.peripheral(self, didWriteValueFor: characteristic, error: error)
    }
    public func sendReady() {
        delegate?.peripheralIsReady(toSendWriteWithoutResponse: self)
    }
    public func receive(_ data: Data, on characteristic: CBCharacteristic, error: Error? = nil) {
        characteristic.value = data
        delegate?.peripheral(self, didUpdateValueFor: characteristic, error: error)
    }
}
