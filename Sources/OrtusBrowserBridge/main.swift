import Foundation
import OrtusCore
import Darwin
import AppKit

/// A browser launches this unprivileged process through Native Messaging. No sockets,
/// Apple Events, administrator helper, browsing history, or page content are involved.
@main
struct OrtusBrowserBridge {
    struct Hello: Decodable { let type: String; let clientID: String; let browser: String }

    struct OpenRequest: Decodable { let type: String; let destination: String }
    struct Status: Decodable { let type: String; let state: String }
    actor Acknowledgement {
        var state = "connecting"
        var sourceApp = BuildProfile.name
        func source(_ name: String?) { if let name { sourceApp = name } }
        func accept(_ data: Data) {
            if let request = try? JSONDecoder().decode(OpenRequest.self, from: data), request.type == "open", ["focus", "browser"].contains(request.destination) {
                let schemes = ["Ortus Native":"ortus-native", "Ortus Glass":"ortus-glass", "Ortus Preview":"ortus-preview", "Ortus":"ortus"]
                let scheme = schemes[sourceApp] ?? schemes[BuildProfile.name] ?? "ortus-preview"
                let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["\(scheme)://\(request.destination)"]
                process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
                try? process.run()
                return
            }
            guard let message = try? JSONDecoder().decode(Status.self, from: data), message.type == "status",
                  ["ready", "error"].contains(message.state) else { return }
            state = message.state
        }
    }

    static func readExactly(_ count: Int) throws -> Data? {
        var data = Data()
        while data.count < count {
            guard let part = try FileHandle.standardInput.read(upToCount: count - data.count), !part.isEmpty else { return nil }
            data.append(part)
        }
        return data
    }
    static func readMessage() throws -> Data? {
        guard let header = try readExactly(4), let size = NativeMessage.length(header) else { return nil }
        return try readExactly(size)
    }

    static func main() async {
        // Testing uses an isolated directory, never the user's live policy.
        let directory: URL
        if let i = CommandLine.arguments.firstIndex(of: "--state-directory"), CommandLine.arguments.count > i + 1 {
            directory = URL(fileURLWithPath: CommandLine.arguments[i + 1], isDirectory: true)
        } else {
            directory = BrowserPaths.directory(preview: Bundle.main.object(forInfoDictionaryKey: "OrtusPreviewBuild") as? Bool == true)
        }
        do {
            guard let input = try readMessage(), let hello = try? JSONDecoder().decode(Hello.self, from: input),
                  hello.type == "hello", UUID(uuidString: hello.clientID) != nil else { return }
            let clients = directory.appendingPathComponent("clients", isDirectory: true)
            try BrowserPaths.prepare(clients)
            let clientURL = clients.appendingPathComponent(hello.clientID + ".json")
            let parent = NSRunningApplication(processIdentifier: getppid())?.bundleIdentifier ?? ""
            let detected = parent.hasPrefix("company.thebrowser.Browser") ? "Arc" : parent.hasPrefix("com.brave") ? "Brave" : parent.hasPrefix("com.microsoft.edgemac") ? "Edge" : nil
            let browser = detected ?? (["Chrome", "Arc", "Edge", "Brave", "Chromium"].contains(hello.browser) ? hello.browser : "Chromium")
            let acknowledgement = Acknowledgement()
            // Exit when the browser closes its port; an orphan must not claim to be connected.
            Task.detached {
                while let data = try? readMessage() { await acknowledgement.accept(data) }
                try? FileManager.default.removeItem(at: clientURL)
                exit(0)
            }
            var previous: Data?
            var lastHeartbeat = Date.distantPast
            // A browser keeps this process alive across app updates. When the installed
            // helper changes, exit so the extension reconnects to the new version.
            let executable = Bundle.main.executablePath
            let modified = { (path: String) in (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date }
            let launchedVersion = executable.flatMap(modified)
            while true {
                let now = Date()
                if let executable, now.timeIntervalSince(lastHeartbeat) >= 5, modified(executable) != launchedVersion {
                    try? FileManager.default.removeItem(at: clientURL)
                    exit(0)
                }
                let url = directory.appendingPathComponent("policy.json")
                var policy = BrowserPolicy(sessions: [], now: now)
                policy.heartbeatExpiresAt = 0 // missing/invalid policy means Ortus is offline
                if let data = try? Data(contentsOf: url), data.count <= NativeMessage.maximumBytes,
                   let decoded = try? JSONDecoder().decode(BrowserPolicy.self, from: data) {
                    policy = decoded.effective(at: now)
                }
                if policy.heartbeatExpiresAt <= now.timeIntervalSince1970 {
                    let folder = directory.appendingPathComponent("presence")
                    let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
                    let presence = urls.compactMap { url -> BrowserPresence? in
                        guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(BrowserPresence.self, from: data),
                              value.updatedAt <= now.timeIntervalSince1970 + 5, now.timeIntervalSince1970 - value.updatedAt < 20 else { return nil }
                        return value
                    }.max { $0.startedAt < $1.startedAt }
                    if let presence {
                        policy = BrowserPolicy(sessions: [], now: Date(timeIntervalSince1970: presence.updatedAt), appearance: presence.appearance, appName: presence.appName)
                    }
                }
                policy.browserName = browser
                await acknowledgement.source(policy.appName)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let output = try encoder.encode(policy)
                if output != previous || now.timeIntervalSince(lastHeartbeat) >= 5 {
                    try FileHandle.standardOutput.write(contentsOf: NativeMessage.frame(output))
                    try BrowserPaths.write(BrowserClient(id: hello.clientID, browser: browser, updatedAt: now.timeIntervalSince1970, state: await acknowledgement.state), to: clientURL)
                    previous = output; lastHeartbeat = now
                }
                try await Task.sleep(for: .milliseconds(500))
            }
        } catch {
            // stdout is reserved for framed protocol messages.
            try? FileHandle.standardError.write(contentsOf: Data("Ortus browser connection ended: \(error.localizedDescription)\n".utf8))
        }
    }
}
