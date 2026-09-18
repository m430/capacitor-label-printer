import Foundation

@main
struct StatusMapperTests {
    static func main() {
        let status = IOSStatusMapper().toPluginStatus(
            connected: true, message: "status unknown", raw: nil
        )
        guard status["ready"] == nil else {
            fputs("FAIL: connection alone must not report ready=true\n", stderr)
            exit(1)
        }
        print("PASS: unknown printer readiness remains unknown")
    }
}
