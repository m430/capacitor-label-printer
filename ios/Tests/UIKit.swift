import Foundation

public final class UIApplication {
    public static let shared = UIApplication()
    public static let openSettingsURLString = "app-settings:"
    public func open(_ url: URL, completionHandler: ((Bool) -> Void)?) { completionHandler?(true) }
}
