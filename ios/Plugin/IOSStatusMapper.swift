import Foundation

struct IOSStatusMapper {
    func toPluginStatus(connected: Bool, statusCode: Int?, message: String, raw: String?) -> [String: Any] {
        var status: [String: Any] = [
            "connected": connected,
            "ready": connected,
            "paperOut": false,
            "coverOpen": false,
            "overheating": false,
            "message": message
        ]

        if let raw {
            status["raw"] = raw
        } else if let statusCode {
            status["raw"] = statusCode
        }

        guard connected, let statusCode else {
            return status
        }

        switch statusCode {
        case 0:
            status["ready"] = false
            status["coverOpen"] = true
        case 1:
            status["ready"] = false
            status["paperOut"] = true
        case 2:
            status["ready"] = false
            status["overheating"] = true
        default:
            break
        }

        return status
    }

    func message(for statusCode: Int) -> String {
        switch statusCode {
        case 0:
            return "cover open"
        case 1:
            return "paper out"
        case 2:
            return "overheating"
        case 3:
            return "printing"
        case 4:
            return "battery low"
        default:
            return "ready"
        }
    }
}
