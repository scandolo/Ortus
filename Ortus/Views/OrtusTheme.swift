import AppKit
import SwiftUI

// MARK: - Design System

enum OrtusTheme {
    // MARK: Colors — Accent (calm green, adaptive light/dark)

    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.40, green: 0.65, blue: 0.45, alpha: 1)   // #66A673
            : NSColor(red: 0.24, green: 0.42, blue: 0.27, alpha: 1)   // #3D6B44
    })

    static let accentSoft = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.24, green: 0.42, blue: 0.27, alpha: 0.20) // dark: subtle green overlay
            : NSColor(red: 0.82, green: 0.89, blue: 0.83, alpha: 1)    // #D1E3D4
    })

    static let accentHover = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.35, green: 0.58, blue: 0.40, alpha: 1)   // #599466
            : NSColor(red: 0.18, green: 0.35, blue: 0.22, alpha: 1)   // #2E5938
    })

    // MARK: Colors — Semantic

    static let warning = Color(red: 0.77, green: 0.64, blue: 0.42)   // #C4A46C gentle amber
    static let danger  = Color(red: 0.77, green: 0.45, blue: 0.45)   // #C47272 muted red
    static let success = accent

    // MARK: Colors — Text

    /// Use alongside SwiftUI .primary / .secondary for placeholders & disabled states.
    static let textMuted = Color(red: 0.71, green: 0.71, blue: 0.69) // #B5B5B0

    // MARK: Colors — Surface (transparent adaptive overlays for popover context)

    static let cardFill  = Color.primary.opacity(0.05)
    static let hoverFill = Color.primary.opacity(0.08)
    static let border    = Color.primary.opacity(0.10)

    // MARK: Spacing (4px base grid)

    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 16
    static let spacingLG: CGFloat = 24
    static let spacingXL: CGFloat = 32

    // MARK: Corner Radii (continuous style everywhere)

    static let radiusSM: CGFloat = 6
    static let radiusMD: CGFloat = 10
    static let radiusLG: CGFloat = 14
    static let radiusXL: CGFloat = 20

    // MARK: Shadows

    static func shadowSM(_ content: some View) -> some View {
        content.shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }

    static func shadowMD(_ content: some View) -> some View {
        content.shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
}

// MARK: - Card Modifier

struct OrtusCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(OrtusTheme.spacingMD)
            .background(
                RoundedRectangle(cornerRadius: OrtusTheme.radiusLG, style: .continuous)
                    .fill(OrtusTheme.cardFill)
            )
            .clipShape(RoundedRectangle(cornerRadius: OrtusTheme.radiusLG, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: OrtusTheme.radiusLG, style: .continuous)
                    .stroke(OrtusTheme.border, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }
}

extension View {
    func ortusCard() -> some View {
        modifier(OrtusCardModifier())
    }
}

// MARK: - Primary Button Style

struct OrtusPrimaryButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous)
                    .fill(isHovering || configuration.isPressed
                          ? OrtusTheme.accentHover
                          : OrtusTheme.accent)
            )
            .onHover { hovering in isHovering = hovering }
    }
}

// MARK: - Secondary Button Style

struct OrtusSecondaryButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous)
                    .fill(isHovering || configuration.isPressed
                          ? OrtusTheme.hoverFill
                          : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous)
                    .stroke(OrtusTheme.border, lineWidth: 1)
            )
            .onHover { hovering in isHovering = hovering }
    }
}

// MARK: - Ghost Button Style

struct OrtusGhostButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(isHovering || configuration.isPressed ? .primary : .secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous)
                    .fill(isHovering || configuration.isPressed
                          ? OrtusTheme.cardFill
                          : Color.clear)
            )
            .onHover { hovering in isHovering = hovering }
    }
}

// MARK: - Text Field Style

struct OrtusTextFieldStyle: TextFieldStyle {
    @FocusState private var isFocused: Bool

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .focused($isFocused)
            .background(
                RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous)
                    .fill(OrtusTheme.cardFill)
            )
            .clipShape(RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous)
                    .stroke(isFocused ? OrtusTheme.accent : OrtusTheme.border, lineWidth: 1)
            )
            .shadow(
                color: isFocused ? OrtusTheme.accent.opacity(0.25) : .clear,
                radius: 3,
                y: 0
            )
    }
}

// MARK: - Empty State

struct OrtusEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: OrtusTheme.spacingMD) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(OrtusTheme.textMuted)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(OrtusTheme.spacingMD)
    }
}

// MARK: - Vibrant Background (fixes opaque NSHostingView in MenuBarExtra panels)

struct VibrantBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Section Header

struct OrtusSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .tracking(0.5)
            .foregroundStyle(.secondary)
    }
}
