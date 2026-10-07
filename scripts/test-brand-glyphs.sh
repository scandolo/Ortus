#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --target OrtusCore
TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT
cat > "$TEMP/Checks.swift" <<'SWIFT'
import OrtusCore

@main
struct BrandGlyphChecks {
    @MainActor static func main() {
        for (id, domain) in [("youtube", "youtube.com"), ("twitch", "twitch.tv"), ("netflix", "netflix.com"),
                             ("spotify", "spotify.com"), ("discord", "discord.com"), ("telegram", "telegram.org")] {
            precondition(BrandGlyph.websiteID(for: "www." + domain) == id)
            precondition(BrandGlyph.websiteID(for: domain.uppercased() + ".") == id)
            precondition(BrandGlyph.websiteID(for: "not" + domain) == nil)
            precondition(BrandGlyph.websiteID(for: domain + ".example.com") == nil)
        }
        precondition(BrandGlyph.websiteID(for: "youtu.be") == "youtube")
        precondition(BrandGlyph.websiteID(for: "discord.gg") == "discord")
        precondition(BrandGlyph.websiteID(for: "t.me") == "telegram")
        precondition(BrandGlyph.websiteID(for: "example.com") == nil)
        precondition(BrandGlyph.websiteID(for: "mail.google.com") == "gmail")
        precondition(BrandGlyph.websiteID(for: "mail.google.com.example.com") == nil)
        precondition(ModeGlyphs.identifiers(for: .init(websites: ["mail.google.com"])) == ["gmail"])
        precondition(ModeGlyphs.identifiers(for: .init(websites: ["youtube.com", "music.youtube.com", "youtu.be"])) == ["youtube"])
        precondition(ModeGlyphs.identifiers(for: .init(websites: ["example.com"])) == [])
        precondition(ModeGlyphs.identifiers(for: .init(websites: ["youtube.com", "twitch.tv", "netflix.com", "spotify.com"])) == ["netflix", "spotify", "twitch"])
        precondition(ModeGlyphs.identifiers(for: FocusMode.social.blocked) == ["linkedin", "x", "instagram"])
        let spotify = BlockedApplication(bundleID: "com.spotify.client", name: "Spotify")
        precondition(BrandGlyph.applicationID(for: spotify) == "spotify")
        precondition(BrandGlyph.applicationID(for: .init(bundleID: "com.hnc.Discord", name: "Discord")) == "discord")
        for bundle in ["ru.keepcoder.Telegram", "com.tdesktop.Telegram"] {
            precondition(BrandGlyph.applicationID(for: .init(bundleID: bundle, name: "Telegram")) == "telegram")
        }
        precondition(BrandGlyph.applicationID(for: .slack) == "slack")
        precondition(BrandGlyph.applicationID(for: .init(bundleID: "com.example.other", name: "Spotify")) == nil)
        precondition(ModeGlyphs.identifiers(for: .init(websites: ["spotify.com"], applications: [spotify])) == ["spotify"])
        precondition(ModeGlyphs.identifiers(for: .init(applications: [spotify])) == ["spotify"])
        print("PASS: six website brands, domain boundaries, aliases, app identities, deduplication and three-mark limit")
    }
}
SWIFT
swiftc -parse-as-library -I .build/debug/Modules .build/debug/OrtusCore.build/*.swift.o \
    Ortus/Views/OrtusTheme.swift Ortus/Views/BrandGlyph.swift "$TEMP/Checks.swift" -o "$TEMP/checks"
"$TEMP/checks"
