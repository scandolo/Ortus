import SwiftUI

/// Faithful in-app mock of how a Slack custom status renders, so users can see what
/// teammates will see before kicking off a focus session.
///
/// Two contexts are shown stacked:
///   1. A message row — avatar, bold name, tiny emoji glyph next to the name (this
///      is the most visible surface; the emoji shows in every channel message).
///   2. The status pill — emoji + full status text, mirroring Slack's
///      hover/profile presentation where the text becomes visible.
///
/// Renders entirely in SwiftUI (no Slack assets) so it's licence-clean and updates
/// live with the user's choices.
struct SlackStatusPreview: View {
    let statusText: String
    let emojiCode: String
    let userName: String
    let dndEnabled: Bool

    private var glyph: String {
        // Slack's documented default when no emoji is set is the speech balloon.
        EmojiCatalog.glyph(for: emojiCode) ?? "💬"
    }

    private var trimmedText: String {
        statusText.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            messageRow
            statusPillRow
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous)
                .fill(slackCanvas)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous)
                .strokeBorder(OrtusTheme.hairline, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            Text("Slack preview")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(.black.opacity(0.05))
                )
                .padding(8)
        }
    }

    // MARK: - Message row

    /// A trimmed-down replica of a Slack channel message row: avatar, name, tiny
    /// status emoji, timestamp. Status emoji placement matches Slack — right after
    /// the display name, before the timestamp.
    private var messageRow: some View {
        HStack(alignment: .top, spacing: 8) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(userName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(slackBodyText)
                    // Status emoji as Slack renders it inline next to the name.
                    Text(glyph)
                        .font(.system(size: 12))
                    // Tiny DND bell-off cue, like Slack shows a sleep moon next to
                    // names of muted users.
                    if dndEnabled {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(slackMuted)
                    }
                    Text("10:42 AM")
                        .font(.system(size: 11))
                        .foregroundStyle(slackMuted)
                }
                Text("Heads down on Ortus.")
                    .font(.system(size: 13))
                    .foregroundStyle(slackBodyText.opacity(0.85))
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Status pill row

    /// Slack's hover/profile presentation: the emoji + status text on a subtle
    /// pill. This is where the status TEXT becomes visible to teammates.
    private var statusPillRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(slackMuted)
            HStack(spacing: 6) {
                Text(glyph)
                    .font(.system(size: 12))
                Text(trimmedText.isEmpty ? "(no status text)" : trimmedText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(trimmedText.isEmpty ? slackMuted : slackBodyText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(slackPillFill)
            )
            .overlay(
                Capsule().strokeBorder(slackPillBorder, lineWidth: 1)
            )
            Text("on hover / profile")
                .font(.system(size: 10))
                .foregroundStyle(slackMuted)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Avatar

    private var avatar: some View {
        let initial = userName.first.map(String.init)?.uppercased() ?? "Y"
        return Text(initial)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.36, green: 0.18, blue: 0.50),  // Slack aubergine
                                Color(red: 0.50, green: 0.26, blue: 0.62),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }

    // MARK: - Slack-like palette
    //
    // Adaptive light/dark to match the user's macOS appearance, but tuned to read
    // as "this is Slack" — white-ish in light mode, near-black in dark mode, with
    // the muted gray Slack uses for timestamps and metadata.

    private var slackCanvas: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1)
                : NSColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1)
        })
    }

    private var slackBodyText: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 0.92, alpha: 1)
                : NSColor(red: 0.11, green: 0.13, blue: 0.16, alpha: 1)
        })
    }

    private var slackMuted: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 0.58, alpha: 1)
                : NSColor(red: 0.38, green: 0.42, blue: 0.48, alpha: 1)
        })
    }

    private var slackPillFill: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1.0, alpha: 0.06)
                : NSColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1)
        })
    }

    private var slackPillBorder: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.10)
                : NSColor(red: 0.86, green: 0.88, blue: 0.90, alpha: 1)
        })
    }
}
