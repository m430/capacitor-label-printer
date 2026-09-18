import Foundation

struct IOSStatusMapper {
    func toPluginStatus(connected: Bool, message: String, raw: Data?) -> [String: Any] {
        var status: [String: Any] = ["connected": connected, "message": message]
        if !connected { status["ready"] = false }
        if let raw, !raw.isEmpty {
            status["raw"] = [
                "data": String(data: raw, encoding: .utf8).map { $0 as Any } ?? Array(raw),
                "correlated": false
            ]
        }
        return status
    }
}
