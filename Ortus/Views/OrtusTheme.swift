import AppKit
import SwiftUI

// MARK: - Design System
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │  ORTUS VISUAL GUIDELINES — Sunrise palette + lifted glass cards    │
// │                                                                     │
// │  1. CARDS LIFT: Cards use OrtusTheme.cardSurface — an adaptive      │
// │     color that's clearly LIGHTER than the popover background in     │
// │     both light and dark mode. Cards float above the canvas, never   │
// │     sink below it.                                                  │
// │                                                                     │
// │  2. WARM ACCENT: Sunrise amber for CTAs, primary affordances, and   │
// │     the focus hero. Cool sage for "all-clear" semantic moments.     │
// │     Don't introduce other accents — keep the palette tight.         │
// │                                                                     │
// │  3. SHAPE LANGUAGE: Continuous corner radius everywhere.            │
// │                                                                     │
// │  4. NO DIVIDERS: Use spacing or distinct cards. Lines fight glass.  │
// │                                                                     │
// │  5. BUTTON HIERARCHY:                                               │
// │     - OrtusPrimaryButtonStyle → tinted-amber capsule (one CTA / view)│
// │     - OrtusSecondaryButtonStyle → glass capsule                     │
// │     - OrtusGhostButtonStyle → borderless                            │
// │                                                                     │
// │  6. TEXT FIELDS: Always OrtusTextFieldStyle().                      │
// │                                                                     │
// │  7. TYPOGRAPHY: Headers use uppercase tracked caption2.semibold.    │
// │     Hero text uses SF Rounded thin at large sizes. Body weights     │
// │     err on the slightly-bold side for a more intentional feel.      │
// │                                                                     │
// │  8. TOKENS: Use only OrtusTheme spacing/radius/color tokens.        │
// └─────────────────────────────────────────────────────────────────────┘

enum OrtusTheme {
    // MARK: Colors — Accent (sunrise amber, adaptive light/dark)

    /// Warm sunrise amber. The colour of the rising sun on the horizon.
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.98, green: 0.62, blue: 0.28, alpha: 1)   // #FA9F47 — bright in dark
            : NSColor(red: 0.88, green: 0.45, blue: 0.15, alpha: 1)   // #E07327 — saturated in light
    })

    static let accentSoft = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.98, green: 0.62, blue: 0.28, alpha: 0.24)
            : NSColor(red: 0.88, green: 0.45, blue: 0.15, alpha: 0.18)
    })

    static let accentHover = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 1.00, green: 0.72, blue: 0.42, alpha: 1)
            : NSColor(red: 0.76, green: 0.36, blue: 0.10, alpha: 1)
    })

    /// Twilight indigo — a deep evening-sky companion accent for emphasis and badges.
    static let twilight = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.55, green: 0.60, blue: 0.95, alpha: 1)
            : NSColor(red: 0.32, green: 0.36, blue: 0.72, alpha: 1)
    })

    // MARK: Colors — Semantic

    static let warning = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.95, green: 0.78, blue: 0.40, alpha: 1)
            : NSColor(red: 0.78, green: 0.55, blue: 0.20, alpha: 1)
    })

    static let danger = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.95, green: 0.50, blue: 0.50, alpha: 1)
            : NSColor(red: 0.78, green: 0.30, blue: 0.30, alpha: 1)
    })

    /// Calm sage — the colour of post-sunrise vegetation. Used for "all clear / connected" states.
    static let success = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.52, green: 0.78, blue: 0.58, alpha: 1)
            : NSColor(red: 0.28, green: 0.52, blue: 0.36, alpha: 1)
    })

    // MARK: Colors — Surfaces

    /// Popover canvas. SOLID adaptive color — does not let the desktop wallpaper bleed through
    /// in light mode. This is what fixes the "weird tint depending on what's behind the menu bar"
    /// problem with vibrant materials.
    static let canvas = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1.0)   // #1A1A1C — warm near-black
            : NSColor(red: 0.96, green: 0.94, blue: 0.91, alpha: 1.0)   // #F5EFE8 — warm cream
    })

    /// Card / elevated surface. Sits ON the canvas with a clear contrast step.
    /// Light: pure white. Dark: slightly-lifted dark gray. Both fully opaque.
    static let cardSurface = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1.0)   // #292929 — lifted dark
            : NSColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1.0)   // pure white
    })

    /// Nested input surface — recessed below the card. Subtly darker than the card,
    /// not jarring, but enough to read as "input field".
    static let inputSurface = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1.0)   // deeper than card
            : NSColor(red: 0.94, green: 0.92, blue: 0.88, alpha: 1.0)   // warm pale gray
    })

    /// Inner highlight — gives surfaces a thin top edge of light. Only meaningful in dark mode.
    static let innerHighlight = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.10)
            : NSColor.white.withAlphaComponent(0.0)
    })
    static let innerHighlightStrong = Color.white.opacity(0.20)

    /// Thin border on cards / inputs.
    static let hairline = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.08)
            : NSColor.black.withAlphaComponent(0.08)
    })

    // MARK: Colors — Text

    static let textMuted = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.72, green: 0.70, blue: 0.66, alpha: 1)
            : NSColor(red: 0.40, green: 0.38, blue: 0.36, alpha: 1)
    })

    // MARK: Spacing (4pt grid)

    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 16
    static let spacingLG: CGFloat = 22
    static let spacingXL: CGFloat = 32

    // MARK: Corner Radii (continuous everywhere)

    static let radiusSM: CGFloat = 8
    static let radiusMD: CGFloat = 12
    static let radiusLG: CGFloat = 18
    static let radiusXL: CGFloat = 26

    // MARK: - Typography Scale
    //
    // The ONLY type tokens any view should use. Every Text/Label in every view
    // must reach for one of these. No raw .system(size:) or .caption / .subheadline
    // / .headline shortcuts — that's what produced the size drift across screens.

    enum Typo {
        /// 54pt rounded light — the focus timer. One per app.
        static let hero        = Font.system(size: 54, weight: .light, design: .rounded)

        /// 30pt rounded medium — emphasis numbers (e.g. countdown ring secondary).
        static let display     = Font.system(size: 30, weight: .medium, design: .rounded)

        /// 22pt bold — primary screen titles ("Ready when you are", "No schedules yet").
        static let title       = Font.system(size: 22, weight: .bold)

        /// 15pt semibold — card titles, list-row primaries ("Focus Time", "Connected to Acme").
        static let headline    = Font.system(size: 15, weight: .semibold)

        /// 13pt regular — paragraphs, descriptions, helper text.
        static let body        = Font.system(size: 13, weight: .regular)

        /// 13pt medium — body that needs a touch more emphasis (toggle labels, input labels).
        static let bodyMedium  = Font.system(size: 13, weight: .medium)

        /// 12pt regular — secondary lines under headlines (schedule day summary, timestamps).
        static let caption     = Font.system(size: 12, weight: .regular)

        /// 11pt medium — small metadata (footer text, expirations, "1 schedule active").
        static let meta        = Font.system(size: 11, weight: .medium)

        /// 11pt bold uppercase — section headers. Use with .tracking(1.4).
        static let section     = Font.system(size: 11, weight: .bold)

        /// 11pt rounded semibold — pill badges ("Slack: Ortus mode", "+15 min").
        static let badge       = Font.system(size: 11, weight: .semibold, design: .rounded)

        /// 13pt semibold — button text.
        static let button      = Font.system(size: 13, weight: .semibold)

        /// 14pt semibold — primary CTA button text.
        static let buttonPrimary = Font.system(size: 14, weight: .semibold)
    }
}

// MARK: - Card (lifted glass surface)

struct OrtusCardModifier: ViewModifier {
    var tinted: Color? = nil

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: OrtusTheme.radiusLG, style: .continuous)
        return content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OrtusTheme.spacingMD)
            .background(shape.fill(OrtusTheme.cardSurface))
            .background(shape.fill((tinted ?? .clear).opacity(0.10)))
            .overlay(shape.strokeBorder(OrtusTheme.hairline, lineWidth: 1))
            .overlay(
                // Top-edge highlight — visible in dark mode (gives lit-from-above feel),
                // invisible in light mode where the hairline carries the definition.
                shape.strokeBorder(
                    LinearGradient(
                        colors: [OrtusTheme.innerHighlight, .clear],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: 1
                )
            )
            .clipShape(shape)
            .shadow(color: .black.opacity(0.12), radius: 14, y: 5)
            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}

extension View {
    func ortusCard() -> some View {
        modifier(OrtusCardModifier())
    }

    func ortusCard(tint: Color) -> some View {
        modifier(OrtusCardModifier(tinted: tint))
    }
}

// MARK: - Primary Button (warm amber CTA)

struct OrtusPrimaryButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let active = isHovering || pressed
        return configuration.label
            .font(OrtusTheme.Typo.buttonPrimary)
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(active ? OrtusTheme.accentHover : OrtusTheme.accent)
            )
            .overlay(
                Capsule()
                    .strokeBorder(OrtusTheme.innerHighlightStrong, lineWidth: 1)
            )
            .clipShape(Capsule())
            .shadow(color: OrtusTheme.accent.opacity(active ? 0.50 : 0.30), radius: active ? 14 : 8, y: active ? 4 : 2)
            .scaleEffect(pressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.14), value: pressed)
            .animation(.easeOut(duration: 0.18), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

// MARK: - Secondary Button (glass capsule)

struct OrtusSecondaryButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let active = isHovering || pressed
        return configuration.label
            .font(OrtusTheme.Typo.button)
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Capsule().fill(OrtusTheme.cardSurface))
            .background(Capsule().fill(active ? Color.primary.opacity(0.06) : .clear))
            .overlay(
                Capsule().strokeBorder(OrtusTheme.hairline, lineWidth: 1)
            )
            .clipShape(Capsule())
            .scaleEffect(pressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.14), value: pressed)
            .animation(.easeOut(duration: 0.18), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

// MARK: - Ghost Button (borderless)

struct OrtusGhostButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let active = isHovering || pressed
        return configuration.label
            .font(OrtusTheme.Typo.meta)
            .foregroundStyle(active ? .primary : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(active ? Color.primary.opacity(0.06) : .clear)
            )
            .clipShape(Capsule())
            .scaleEffect(pressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.14), value: pressed)
            .animation(.easeOut(duration: 0.18), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

// MARK: - Text Field (nested input — slightly recessed)

struct OrtusTextFieldStyle: TextFieldStyle {
    @FocusState private var isFocused: Bool

    func _body(configuration: TextField<Self._Label>) -> some View {
        let shape = RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous)
        return configuration
            .textFieldStyle(.plain)
            .font(OrtusTheme.Typo.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .focused($isFocused)
            .background(shape.fill(OrtusTheme.inputSurface))
            .overlay(
                shape.strokeBorder(isFocused ? OrtusTheme.accent : OrtusTheme.hairline, lineWidth: isFocused ? 1.5 : 1)
            )
            .clipShape(shape)
            .shadow(color: isFocused ? OrtusTheme.accent.opacity(0.30) : .clear, radius: 4, y: 0)
            .animation(.easeOut(duration: 0.18), value: isFocused)
    }
}

// MARK: - Floating Toolbar (bottom input bars)

struct OrtusFloatingToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, OrtusTheme.spacingMD)
            .padding(.vertical, OrtusTheme.spacingSM)
            .background(Capsule().fill(OrtusTheme.cardSurface))
            .overlay(
                Capsule().strokeBorder(OrtusTheme.hairline, lineWidth: 1)
            )
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
            .padding(.horizontal, OrtusTheme.spacingMD)
            .padding(.bottom, OrtusTheme.spacingSM)
    }
}

extension View {
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
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(OrtusTheme.Typo.title)
            Text(message)
                .font(OrtusTheme.Typo.body)
                .foregroundStyle(OrtusTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OrtusTheme.spacingLG)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(OrtusTheme.spacingMD)
    }
}

// MARK: - Popover Background

/// Solid adaptive canvas for the MenuBarExtra popover, with a subtle sunrise-glow gradient
/// at the top for warmth. Does NOT use NSVisualEffectView — translucent materials let the
/// desktop wallpaper bleed through and shift the popover's color unpredictably. A solid
/// canvas keeps the appearance consistent regardless of what's behind the menu bar.
struct VibrantBackground: View {
    var body: some View {
        ZStack {
            OrtusTheme.canvas
            // Subtle warm glow at the top — the "first light on a horizon" cue.
            LinearGradient(
                colors: [
                    OrtusTheme.accentSoft.opacity(0.5),
                    OrtusTheme.accentSoft.opacity(0.15),
                    .clear
                ],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Section Header

struct OrtusSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(OrtusTheme.Typo.section)
            .tracking(1.4)
            .foregroundStyle(OrtusTheme.textMuted)
    }
}
