import AppKit
import SwiftUI

// MARK: - Design System
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │  ORTUS VISUAL GUIDELINES — READ BEFORE MODIFYING ANY VIEW         │
// │                                                                     │
// │  1. SHAPE LANGUAGE: Everything is rounded. Every container, card,  │
// │     input field, button, and the popover itself uses continuous     │
// │     corner radius (style: .continuous) — Apple's "supercircle".    │
// │     Never use sharp corners or default RoundedRectangle without    │
// │     style: .continuous.                                             │
// │                                                                     │
// │  2. NO DIVIDERS: Never use SwiftUI Divider(). Separate sections    │
// │     with spacing (spacingSM/spacingMD) or by placing content in    │
// │     distinct .ortusCard() containers. Straight lines break the     │
// │     rounded visual language.                                        │
// │                                                                     │
// │  3. FLOATING ELEMENTS: Toolbars, input bars, and action bars       │
// │     should be .ortusCard() shapes floating with padding around     │
// │     them — never edge-to-edge strips separated by lines.           │
// │                                                                     │
// │  4. NO OPAQUE BACKGROUNDS: This app runs inside a MenuBarExtra     │
// │     popover with VibrantBackground (NSVisualEffectView). All       │
// │     surface colors must be transparent overlays (cardFill,         │
// │     hoverFill, border). Never use Color(nsColor: .controlBg) or   │
// │     .textFieldStyle(.roundedBorder) — they draw opaque AppKit      │
// │     backgrounds that break dark mode.                               │
// │                                                                     │
// │  5. BUTTON HIERARCHY:                                               │
// │     - OrtusPrimaryButtonStyle → main CTA (one per view max)        │
// │     - OrtusSecondaryButtonStyle → secondary actions (save, add)    │
// │     - OrtusGhostButtonStyle → tertiary/cancel/destructive          │
// │     Never use default SwiftUI .bordered or unstyled Button().      │
// │                                                                     │
// │  6. TEXT FIELDS: Always use OrtusTextFieldStyle() for TextField    │
// │     and SecureField. It uses .plain + custom SwiftUI background.   │
// │                                                                     │
// │  7. POPOVER SHAPE: The MenuBarExtra popover window handles its     │
// │     own shape — do NOT clip ContentView with .clipShape().         │
// │     Let macOS manage the popover chrome.                            │
// │                                                                     │
// │  8. TEXT COLORS: Never use SwiftUI .secondary or .tertiary for     │
// │     foreground styles — they wash out on light vibrancy. Use       │
// │     OrtusTheme.textSecondary and OrtusTheme.textTertiary instead.  │
// │                                                                     │
// │  9. FONT SIZES: Use explicit .system(size:weight:) for all text.   │
// │     Headers: 15pt semibold. Body: 13pt. Captions: 12pt.           │
// │     Small captions: 11pt. Hero text: 18pt semibold.                │
// │                                                                     │
// │ 10. TOKENS: Use only OrtusTheme spacing/radius/color tokens.       │
// │     Don't hardcode sizes, colors, or corner radii inline.          │
// └─────────────────────────────────────────────────────────────────────┘

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
    static let textMuted = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.62, green: 0.62, blue: 0.60, alpha: 1)   // #9E9E99 dark
            : NSColor(red: 0.45, green: 0.45, blue: 0.43, alpha: 1)   // #73736E light
    })

    // MARK: Colors — Text hierarchy (legible on both light and dark vibrancy)

    /// Primary text — use SwiftUI .primary (fully opaque, always readable).
    /// Secondary text — captions, timestamps, supporting labels.
    static let textSecondary = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1.0, alpha: 0.55)
            : NSColor(white: 0.0, alpha: 0.50)
    })

    /// Tertiary text — disabled, placeholder-level.
    static let textTertiary = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1.0, alpha: 0.35)
            : NSColor(white: 0.0, alpha: 0.35)
    })

    // MARK: Colors — Surface (semi-opaque overlays for popover context — must be
    //        visible over both light and dark desktop wallpapers)

    static let cardFill = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1.0, alpha: 0.06)
            : NSColor(white: 0.0, alpha: 0.05)
    })
    static let hoverFill = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1.0, alpha: 0.10)
            : NSColor(white: 0.0, alpha: 0.08)
    })
    static let border = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1.0, alpha: 0.12)
            : NSColor(white: 0.0, alpha: 0.12)
    })

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
            .font(.system(size: 13, weight: .medium))
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
            .font(.system(size: 13, weight: .medium))
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
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isHovering || configuration.isPressed ? .primary : OrtusTheme.textSecondary)
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

// MARK: - Floating Toolbar Modifier (for input bars, action bars)

struct OrtusFloatingToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, OrtusTheme.spacingMD)
            .padding(.vertical, OrtusTheme.spacingSM)
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
            .padding(.horizontal, OrtusTheme.spacingSM)
            .padding(.bottom, OrtusTheme.spacingSM)
    }
}

extension View {
    /// Use for floating input bars, action bars, and toolbars at the bottom of a view.
    /// Renders as a rounded card shape with outer padding — never a flat edge-to-edge strip.
    func ortusFloatingToolbar() -> some View {
        modifier(OrtusFloatingToolbarModifier())
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
                .foregroundStyle(OrtusTheme.textTertiary)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(OrtusTheme.textSecondary)
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
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(OrtusTheme.textSecondary)
    }
}
