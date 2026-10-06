import AppKit
import OrtusCore

@main
struct AppBlockingChecks {
    @MainActor static func main() async throws {
        let appURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        let blocker = ApplicationBlocker()
        let target = BlockedApplication(bundleID: "com.ortus-test.disposable", name: "Ortus Test Fixture")
        func launch() async throws -> NSRunningApplication {
            try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
        }
        let first = try await launch()
        defer { first.forceTerminate() }
        blocker.update([target])
        try await Task.sleep(for: .seconds(2))
        precondition(first.isTerminated, "Selected app must close even if it declines graceful termination")
        print("PASS: selected app closes, including force-termination fallback")
        let second = try await launch()
        defer { second.forceTerminate() }
        try await Task.sleep(for: .seconds(3))
        precondition(second.isTerminated, "Relaunched selected app must be blocked")
        print("PASS: reopening the app during focus closes it again")
        blocker.finish(relaunch: false)
        let third = try await launch()
        defer { third.forceTerminate() }
        try await Task.sleep(for: .seconds(1))
        precondition(!third.isTerminated, "Ending focus must stop the monitor")
        blocker.update([target])
        blocker.update([])
        try await Task.sleep(for: .seconds(2))
        precondition(!third.isTerminated, "A cancelled delayed termination must not kill an unblocked app")
        print("PASS: ending/reverting focus cancels pending kills")
    }
}
