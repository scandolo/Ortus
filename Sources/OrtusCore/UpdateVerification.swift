import Foundation
import Security

/// Where updates come from, and what a downloaded update must be before it replaces
/// the running app. The feed is on our own domain so it can be repointed (for
/// example away from GitHub releases) without shipping a new app.
public enum UpdateFeed {
    public static let url = URL(string: "https://ortusmode.com/update/latest.json")!
    /// Download hosts the feed may point at. The code signature is the real check;
    /// this just keeps the app from fetching from anywhere else.
    static let allowedHosts: Set<String> = ["ortusmode.com", "github.com"]

    public struct Entry: Equatable, Sendable {
        public let version: String
        public let zip: URL
    }

    /// Parse `{"version": "1.2.3", "zip": "https://ortusmode.com/..."}`. Returns nil
    /// for anything malformed or pointing outside the allowed hosts.
    public static func parse(_ data: Data) -> Entry? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawVersion = json["version"] as? String,
              let zipString = json["zip"] as? String,
              let zip = URL(string: zipString), isAllowed(zip) else { return nil }
        let version = rawVersion.hasPrefix("v") ? String(rawVersion.dropFirst()) : rawVersion
        guard !version.isEmpty, version.split(separator: ".").allSatisfy({ Int($0) != nil }) else { return nil }
        return Entry(version: version, zip: zip)
    }

    public static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              let host = url.host?.lowercased() else { return false }
        return allowedHosts.contains(host)
    }

    /// Compare dot-separated version strings numerically (e.g. "1.0.10" > "1.0.9").
    public static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

public enum UpdateVerifier {
    /// Signed by our Developer ID (team XGJ489TRXB) with the release bundle ID.
    /// Previews (`com.ortusmode.preview`) and ad-hoc builds never match.
    public static let requirement =
        #"anchor apple generic and identifier "com.ortusmode.app" and certificate leaf[subject.OU] = "XGJ489TRXB""#

    public enum Failure: Error, Equatable {
        case signature(OSStatus)
        case notNewer(String?)
    }

    /// Check the whole bundle's signature (every architecture, nested code, strict)
    /// against `requirement`, then that its version is newer than `runningVersion`.
    /// Returns the new version.
    @discardableResult
    public static func verify(appAt app: URL, newerThan runningVersion: String) throws -> String {
        var code: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(app as CFURL, [], &code)
        guard status == errSecSuccess, let code else { throw Failure.signature(status) }
        var req: SecRequirement?
        status = SecRequirementCreateWithString(requirement as CFString, [], &req)
        guard status == errSecSuccess, let req else { throw Failure.signature(status) }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        status = SecStaticCodeCheckValidity(code, flags, req)
        guard status == errSecSuccess else { throw Failure.signature(status) }

        // Info.plist is sealed by the signature just checked, so its version is trustworthy.
        let plist = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        let version = plist?["CFBundleShortVersionString"] as? String
        guard let version, UpdateFeed.isVersion(version, newerThan: runningVersion) else {
            throw Failure.notNewer(version)
        }
        return version
    }
}
