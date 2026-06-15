import Foundation

final class IOSPrinterManager {
    private(set) var connected = false
    private(set) var currentDeviceId: String?
    private let mapper = IOSStatusMapper()

    func discoverDevices(namePrefixes: [String]) -> [[String: Any]] {
        let defaults: [String: Any] = [
            "id": "mock-qr365-ble",
            "name": "QR-365-BLE",
            "transport": "ble"
        ]

        guard !namePrefixes.isEmpty else {
            return [defaults]
        }

        return "QR-365-BLE".hasPrefix(namePrefixes[0]) ? [defaults] : []
    }

    func connect(deviceId: String) {
        connected = true
        currentDeviceId = deviceId
    }

    func disconnect() {
        connected = false
        currentDeviceId = nil
    }

    func getConnectionState() -> [String: Any] {
        return ["state": connected ? "connected" : "disconnected"]
    }

    func getStatus() -> [String: Any] {
        return mapper.toPluginStatus(connected: connected, message: connected ? "ready" : "disconnected")
    }

    func print(payload: String, copies: Int) throws {
        if !connected {
            throw NSError(
                domain: "LabelPrinter",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "printer is not connected"]
            )
        }
        if payload.isEmpty || copies < 1 {
            throw NSError(
                domain: "LabelPrinter",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "invalid print payload"]
            )
        }
    }
}
