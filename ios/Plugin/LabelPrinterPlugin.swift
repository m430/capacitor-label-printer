import Foundation
import Capacitor

@objc(LabelPrinterPlugin)
public class LabelPrinterPlugin: CAPPlugin {
    private let manager = IOSPrinterManager()

    @objc func isSupported(_ call: CAPPluginCall) {
        call.resolve(["supported": true])
    }

    @objc func ensurePermissions(_ call: CAPPluginCall) {
        call.resolve(["granted": true])
    }

    @objc func discoverDevices(_ call: CAPPluginCall) {
        let prefixes = call.getArray("namePrefixes", String.self) ?? []
        let timeoutMs = call.getDouble("timeout") ?? 2000
        call.resolve(["devices": manager.discoverDevices(namePrefixes: prefixes, timeoutMs: timeoutMs)])
    }

    @objc func connect(_ call: CAPPluginCall) {
        guard let deviceId = call.getString("deviceId") else {
            call.reject("deviceId is required")
            return
        }

        do {
            try manager.connect(deviceId: deviceId)
            call.resolve()
        } catch {
            call.reject(error.localizedDescription)
        }
    }

    @objc func disconnect(_ call: CAPPluginCall) {
        manager.disconnect()
        call.resolve()
    }

    @objc func getConnectionState(_ call: CAPPluginCall) {
        call.resolve(manager.getConnectionState())
    }

    @objc func print(_ call: CAPPluginCall) {
        do {
            try manager.print(payload: call.getString("payload", ""), copies: call.getInt("copies", 1))
            call.resolve()
        } catch {
            call.reject(error.localizedDescription)
        }
    }

    @objc func getStatus(_ call: CAPPluginCall) {
        call.resolve(manager.getStatus())
    }
}
