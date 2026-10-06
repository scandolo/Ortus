import AppKit
import OrtusCore

@MainActor
final class ApplicationBlocker {
    private var targets: Set<String> = []
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var pending: [pid_t: Task<Void, Never>] = [:]
    private var closedApps: Set<URL> = []

    func update(_ applications: [BlockedApplication]) {
        let next = Set(applications.map(\.bundleID).filter(BlockedApplication.isBlockable))
        guard targets != next else { return }
        targets = next
        for task in pending.values { task.cancel() }
        pending.removeAll()
        if next.isEmpty { stop(); return }
        if observer == nil {
            observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.enforce() }
            }
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.enforce() }
            }
        }
        enforce()
    }

    private func enforce() {
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier, targets.contains(id), !app.isTerminated,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier, pending[app.processIdentifier] == nil else { continue }
            if let url = app.bundleURL { closedApps.insert(url) }
            let pid = app.processIdentifier
            app.terminate()
            pending[pid] = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
                guard let self else { return }
                defer { self.pending[pid] = nil }
                guard self.targets.contains(id), !app.isTerminated else { return }
                app.forceTerminate()
            }
        }
    }

    private func stop() {
        timer?.invalidate(); timer = nil
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }

    func finish(relaunch: Bool) {
        update([])
        let apps = closedApps
        closedApps.removeAll()
        if relaunch {
            for url in apps {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                NSWorkspace.shared.openApplication(at: url, configuration: config)
            }
        }
    }
}
