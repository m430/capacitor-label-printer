import Foundation
import Capacitor
import CoreBluetooth
import UIKit

@objc(LabelPrinterPlugin)
public class LabelPrinterPlugin: CAPPlugin {
    private let manager = IOSPrinterManager()

    @objc func isSupported(_ call: CAPPluginCall) {
        call.resolve(["supported": true])
    }

    @objc override public func checkPermissions(_ call: CAPPluginCall) {
        call.resolve(buildPermissionResult(for: bluetoothAuthorization))
    }

    @objc func ensurePermissions(_ call: CAPPluginCall) {
        let authorization = bluetoothAuthorization
        if authorization == .notDetermined {
            call.resolve([
                "granted": true,
                "canPrompt": true,
                "shouldOpenSettings": false,
                "permissions": [
                    "bluetooth": "prompt"
                ]
            ])
            return
        }

        call.resolve(buildPermissionResult(for: authorization))
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
            try manager.print(payload: call.getString("payload", ""), language: call.getString("language", "tspl"), copies: call.getInt("copies", 1))
            call.resolve()
        } catch {
            call.reject(error.localizedDescription)
        }
    }

    @objc func getStatus(_ call: CAPPluginCall) {
        call.resolve(manager.getStatus())
    }

    @objc func openAppSettings(_ call: CAPPluginCall) {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            call.reject("unable to create app settings url")
            return
        }

        DispatchQueue.main.async {
            UIApplication.shared.open(url) { success in
                if success {
                    call.resolve()
                    return
                }

                call.reject("unable to open app settings")
            }
        }
    }

    private var bluetoothAuthorization: CBManagerAuthorization {
        if #available(iOS 13.0, *) {
            return CBManager.authorization
        }

        return .allowedAlways
    }

    private func buildPermissionResult(for authorization: CBManagerAuthorization) -> [String: Any] {
        let permissionState: String
        let granted: Bool
        let canPrompt: Bool
        let shouldOpenSettings: Bool

        switch authorization {
        case .allowedAlways:
            permissionState = "granted"
            granted = true
            canPrompt = false
            shouldOpenSettings = false
        case .notDetermined:
            permissionState = "prompt"
            granted = false
            canPrompt = true
            shouldOpenSettings = false
        case .denied, .restricted:
            permissionState = "denied"
            granted = false
            canPrompt = false
            shouldOpenSettings = true
        @unknown default:
            permissionState = "prompt"
            granted = false
            canPrompt = true
            shouldOpenSettings = false
        }

        return [
            "granted": granted,
            "canPrompt": canPrompt,
            "shouldOpenSettings": shouldOpenSettings,
            "permissions": [
                "bluetooth": permissionState
            ]
        ]
    }
}
