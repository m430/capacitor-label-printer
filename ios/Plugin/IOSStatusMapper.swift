import Foundation

struct IOSStatusMapper {
    func toPluginStatus(connected: Bool, message: String) -> [String: Any] {
        return [
            "connected": connected,
            "ready": connected,
            "paperOut": false,
            "coverOpen": false,
            "overheating": false,
            "message": message,
            "raw": message
        ]
    }
}
