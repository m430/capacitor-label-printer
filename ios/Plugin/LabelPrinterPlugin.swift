import Foundation
import Capacitor
import CoreBluetooth
import UIKit

@objc(LabelPrinterPlugin)
public class LabelPrinterPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "LabelPrinterPlugin"
    public let jsName = "LabelPrinter"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "isSupported", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "checkPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "ensurePermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "discoverDevices", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "connect", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "disconnect", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getConnectionState", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "print", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getStatus", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "openAppSettings", returnType: CAPPluginReturnPromise)
    ]
    private let manager = IOSPrinterManager()

    @objc func isSupported(_ call: CAPPluginCall) {
        call.resolve(["supported": true])
    }

    @objc override public func checkPermissions(_ call: CAPPluginCall) {
        call.resolve(buildPermissionResult(for: bluetoothAuthorization))
    }

    @objc func ensurePermissions(_ call: CAPPluginCall) {
        manager.ensurePermissions { authorization in
            call.resolve(self.buildPermissionResult(for: authorization))
        }
    }

    @objc func discoverDevices(_ call: CAPPluginCall) {
        let prefixes = call.getArray("namePrefixes", String.self) ?? []
        let timeoutMs = call.getDouble("timeout") ?? 2000
        manager.discoverDevices(namePrefixes: prefixes, timeoutMs: timeoutMs) { result in
            switch result {
            case .success(let devices):
                call.resolve(["devices": devices])
            case .failure(let error):
                call.reject(error.localizedDescription)
            }
        }
    }

    @objc func connect(_ call: CAPPluginCall) {
        guard let deviceId = call.getString("deviceId") else {
            call.reject("deviceId is required")
            return
        }

        manager.connect(deviceId: deviceId) { error in
            if let error {
                call.reject(error.localizedDescription)
                return
            }
            call.resolve()
        }
    }

    @objc func disconnect(_ call: CAPPluginCall) {
        manager.disconnect { error in
            if let error {
                call.reject(error.localizedDescription)
                return
            }
            call.resolve()
        }
    }

    @objc func getConnectionState(_ call: CAPPluginCall) {
        call.resolve(manager.getConnectionState())
    }

    @objc func print(_ call: CAPPluginCall) {
        manager.print(
            payload: call.getString("payload", ""),
            language: call.getString("language", "tspl"),
            copies: call.getInt("copies", 1)
        ) { error in
            if let error {
                call.reject(error.localizedDescription)
                return
            }
            call.resolve()
        }
    }

    @objc func getStatus(_ call: CAPPluginCall) {
        manager.getStatus { status in
            call.resolve(status)
        }
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
        manager.getAuthorization()
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
