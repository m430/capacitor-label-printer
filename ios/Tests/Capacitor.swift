import Foundation

public let CAPPluginReturnPromise = "promise"

@objc public protocol CAPBridgedPlugin {
    var identifier: String { get }
    var jsName: String { get }
    var pluginMethods: [CAPPluginMethod] { get }
}

@objcMembers public final class CAPPluginMethod: NSObject {
    public let name: String
    public let returnType: String
    public init(name: String, returnType: String) {
        self.name = name
        self.returnType = returnType
    }
}

@objcMembers open class CAPPlugin: NSObject {
    open func checkPermissions(_ call: CAPPluginCall) {}
}

public final class CAPPluginCall: NSObject {
    public var options: [String: Any] = [:]
    public private(set) var result: [String: Any]?
    public private(set) var rejection: String?
    public private(set) var resolutions = 0
    public func resolve(_ result: [String: Any] = [:]) { self.result = result; resolutions += 1 }
    public func reject(_ message: String) { rejection = message }
    public func getString(_ key: String) -> String? { options[key] as? String }
    public func getString(_ key: String, _ fallback: String) -> String { getString(key) ?? fallback }
    public func getDouble(_ key: String) -> Double? { options[key] as? Double }
    public func getInt(_ key: String, _ fallback: Int) -> Int { options[key] as? Int ?? fallback }
    public func getArray(_ key: String, _ type: String.Type) -> [String]? { options[key] as? [String] }
}
