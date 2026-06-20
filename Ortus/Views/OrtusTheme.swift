import AppKit
import SwiftUI

// MARK: - Design System — "First Light"
//
// ┌──────────────────────────────────────────────────────────────────────────┐
// │  ORTUS — FIRST LIGHT                                                        │
// │  Ortus, n. (Latin) — the rising of the sun.                                │
// │                                                                            │
// │  A calm, premium, dawn-over-the-horizon aesthetic. The feeling of the      │
// │  quiet moment before the world wakes up. Built natively on Apple's         │
// │  Human Interface Guidelines.                                               │
// │                                                                            │
// │  PRINCIPLES                                                                 │
// │                                                                            │
// │  1. ONE ACCENT. A single warm "first light" coral-amber drives every       │
// │     interactive affordance. The multi-stop DAWN GRADIENT is reserved for   │
// │     brand + hero moments only (the timer aura, the sunmark, the idle       │
// │     state). Never decorate chrome with the gradient.                       │
// │                                                                            │
// │  2. SURFACES LIFT. Cards are LIGHTER than the canvas in both modes and     │
// │     float on a soft, layered elevation scale (e1 → e3). Light defines      │
// │     depth with shadow; dark adds a top inner-highlight for "lit from       │
// │     above."                                                                │
// │                                                                            │
// │  3. CONTINUOUS GEOMETRY. squircle corners everywhere; capsules for pills.  │
// │     No hard dividers — group with space and elevation.                     │
// │                                                                            │
// │  4. QUIET TYPOGRAPHY. SF Pro for text, SF Pro Rounded for the hero clock   │
// │     and display numerals (the friendly, Apple-Clock feel). Tabular figures │
// │     for anything that ticks.                                               │
// │                                                                            │
// │  5. MOTION WITH MEANING. 140–260ms, ease-out in / faster out, spring on    │
// │     press. Respects reduced-motion. Nothing animates just to move.         │
// │                                                                            │
// │  6. TOKENS ONLY. Every view reaches for OrtusTheme.* — never a raw hex,    │
// │     never a bare .system(size:). This file is the single source of truth.  │
// └──────────────────────────────────────────────────────────────────────────┘

enum OrtusTheme {

    // MARK: - Adaptive color helper

    /// Builds an appearance-adaptive Color from a light and dark NSColor.
    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
        NSColor(red: r, green: g, blue: b, alpha: a)
    }

    // MARK: - Accent — "first light" coral-amber

    /// The colour of the sun's first light breaking the horizon. The single
    /// accent for CTAs, selection, focus rings, and active affordances.
    static let accent = adaptive(
        light: rgb(0.86, 0.36, 0.12),   // #DB5C1F — saturated burnt coral
        dark:  rgb(0.99, 0.62, 0.30)    // #FD9E4D — warm glow in dark
    )

    /// Hover / pressed escalation of the accent.
    static let accentHover = adaptive(
        light: rgb(0.74, 0.29, 0.07),   // #BC4A12
        dark:  rgb(1.00, 0.73, 0.46)    // #FFBA75
    )

    /// Low-alpha accent wash for tinted fills, selected pills, soft glows.
    static let accentSoft = adaptive(
        light: rgb(0.86, 0.36, 0.12, 0.14),
        dark:  rgb(0.99, 0.62, 0.30, 0.20)
    )

    /// Twilight indigo — the deep-sky companion. Badges, secondary emphasis.
    static let twilight = adaptive(
        light: rgb(0.31, 0.30, 0.62),   // #4F4D9E
        dark:  rgb(0.62, 0.62, 0.97)    // #9E9EF7
    )

    // MARK: - Semantic

    /// Calm sage — "all clear / connected / done."
    static let success = adaptive(
        light: rgb(0.24, 0.50, 0.34),   // #3D8057
        dark:  rgb(0.50, 0.80, 0.58)    // #80CC94
    )

    /// Gold — "in progress / heads-up."
    static let warning = adaptive(
        light: rgb(0.74, 0.52, 0.14),   // #BD8524
        dark:  rgb(0.96, 0.78, 0.40)    // #F5C766
    )

    /// Deep ember — destructive, hue-shifted toward red but still in the
    /// sunrise family so it reads "careful" without importing a foreign red.
    static let danger = adaptive(
        light: rgb(0.73, 0.22, 0.12),   // #BB381F
        dark:  rgb(0.97, 0.46, 0.32)    // #F87552
    )

    // MARK: - Surfaces (warm dawn paper ↔ deep predawn sky)

    /// Popover canvas. SOLID & adaptive — never lets the desktop wallpaper bleed
    /// through (translucent materials shift the popover's colour depending on
    /// what's behind the menu bar). Light: warm paper. Dark: warm near-black.
    static let canvas = adaptive(
        light: rgb(0.957, 0.941, 0.918), // #F4F0EA — warm dawn paper
        dark:  rgb(0.082, 0.078, 0.094)  // #151418 — predawn sky
    )

    /// A slightly deeper canvas used at the very bottom of the popover so the
    /// background reads as a gentle vertical "sky" wash, lighter at the horizon.
    static let canvasDeep = adaptive(
        light: rgb(0.929, 0.910, 0.882), // #EDE8E1
        dark:  rgb(0.055, 0.051, 0.067)  // #0E0D11
    )

    /// Card / elevated surface. Sits ON the canvas with a clear contrast step.
    static let cardSurface = adaptive(
        light: rgb(1.00, 1.00, 1.00),    // pure white
        dark:  rgb(0.126, 0.118, 0.145)  // #201E25 — warm lifted slate
    )

    /// Raised surface (popovers, the floating nav, hero disc) — one step above a card.
    static let cardRaised = adaptive(
        light: rgb(1.00, 1.00, 1.00),
        dark:  rgb(0.157, 0.149, 0.180)  // #28262E
    )

    /// Nested input surface — recessed below the card.
    static let inputSurface = adaptive(
        light: rgb(0.925, 0.906, 0.875), // #ECE7DF
        dark:  rgb(0.063, 0.059, 0.075)  // #100F13
    )

    // MARK: - Lines & highlights

    /// Top-edge highlight giving surfaces a "lit from above" lip. Dark-mode only.
    static let innerHighlight = adaptive(
        light: NSColor.white.withAlphaComponent(0.0),
        dark:  NSColor.white.withAlphaComponent(0.09)
    )
    static let innerHighlightStrong = Color.white.opacity(0.22)

    /// Hairline border on cards / inputs.
    static let hairline = adaptive(
        light: NSColor.black.withAlphaComponent(0.07),
        dark:  NSColor.white.withAlphaComponent(0.08)
    )

    // MARK: - Text

    static let textMuted = adaptive(
        light: rgb(0.42, 0.39, 0.36),    // warm gray
        dark:  rgb(0.72, 0.70, 0.67)
    )

    // MARK: - Dawn gradient (BRAND / HERO ONLY)

    /// The signature sunrise: predawn indigo → mauve → coral → gold.
    /// Used for the sunmark, the timer aura, the idle hero, the app icon —
    /// never for ordinary chrome.
    static let dawnColors: [Color] = [
        Color(red: 0.17, green: 0.16, blue: 0.36),  // #2B294D predawn indigo
        Color(red: 0.66, green: 0.27, blue: 0.49),  // #A8457D mauve
        Color(red: 0.89, green: 0.39, blue: 0.20),  // #E36333 coral
        Color(red: 0.97, green: 0.74, blue: 0.39)   // #F7BC63 gold
    ]

    static var dawnGradient: LinearGradient {
        LinearGradient(colors: dawnColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Warm horizon glow — used behind the sunmark and the timer.
    static var dawnGlow: RadialGradient {
        RadialGradient(
            colors: [
                Color(red: 0.97, green: 0.74, blue: 0.39).opacity(0.9),
                Color(red: 0.89, green: 0.39, blue: 0.20).opacity(0.5),
                .clear
            ],
            center: .center, startRadius: 0, endRadius: 120
        )
    }

    // MARK: - Spacing (4pt grid)

    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 16
    static let spacingLG: CGFloat = 22
    static let spacingXL: CGFloat = 32

    // MARK: - Corner radii (continuous everywhere)

    static let radiusSM: CGFloat = 10
    static let radiusMD: CGFloat = 14
    static let radiusLG: CGFloat = 20
    static let radiusXL: CGFloat = 28

    // MARK: - Elevation
    //
    // A three-step shadow scale. Cards = e1, floating chrome = e2, modals = e3.
    // Soft, layered, never heavy.

    enum Elevation {
        static func e1(_ shape: some View) -> some View {
            shape
                .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        }
        static func e2(_ shape: some View) -> some View {
            shape
                .shadow(color: .black.opacity(0.16), radius: 18, y: 7)
                .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        }
    }

    // MARK: - Typography
    //
    // The ONLY type tokens any view may use. SF Pro for text; SF Pro Rounded for
    // the hero clock & display numerals. No raw .system(size:) elsewhere.

    enum Typo {
        /// 58pt rounded light — the focus clock. One per app.
        static let hero        = Font.system(size: 58, weight: .light, design: .rounded)
        /// 30pt rounded medium — emphasis numerals (grace countdown, big stats).
        static let display     = Font.system(size: 30, weight: .medium, design: .rounded)
        /// 21pt bold — primary screen titles.
        static let title       = Font.system(size: 21, weight: .bold)
        /// 15pt semibold — card titles, list-row primaries.
        static let headline    = Font.system(size: 15, weight: .semibold)
        /// 13pt regular — body, descriptions, helper text.
        static let body        = Font.system(size: 13, weight: .regular)
        /// 13pt medium — emphasised body (toggle labels, input labels).
        static let bodyMedium  = Font.system(size: 13, weight: .medium)
        /// 12pt regular — secondary lines under headlines.
        static let caption     = Font.system(size: 12, weight: .regular)
        /// 11pt medium — small metadata.
        static let meta        = Font.system(size: 11, weight: .medium)
        /// 11pt bold — section headers. Use with .tracking(1.6) + uppercase.
        static let section     = Font.system(size: 11, weight: .bold)
        /// 11pt rounded semibold — pill badges.
        static let badge       = Font.system(size: 11, weight: .semibold, design: .rounded)
        /// 13pt semibold — secondary button text.
        static let button      = Font.system(size: 13, weight: .semibold)
        /// 14pt semibold — primary CTA text.
        static let buttonPrimary = Font.system(size: 14, weight: .semibold)
    }

    // MARK: - Motion tokens

    enum Motion {
        static let press   = Animation.easeOut(duration: 0.14)
        static let hover   = Animation.easeOut(duration: 0.18)
        static let enter   = Animation.easeOut(duration: 0.24)
        static let springy = Animation.spring(response: 0.34, dampingFraction: 0.74)
    }
}

// MARK: - Ortus Sunmark (original brand glyph)
//
// Our own icon — a half-sun rising over a horizon with rays. Drawn in pure
// SwiftUI so it scales crisply and tints with the brand. Used in the idle hero,
// the About card, and (rasterised) the app + menu-bar icon. The single,
// recognisable Ortus mark across every surface.

struct OrtusSunmark: View {
    /// Fill style for the sun + rays. Pass `.linear(OrtusTheme.dawnGradient)` for
    /// the brand version or a solid `Color` for monochrome contexts.
    enum Fill { case solid(Color); case dawn }

    var fill: Fill = .dawn
    var lineWidth: CGFloat = 0.075   // as a fraction of size
    var showGlow: Bool = true

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            let stroke = s * lineWidth
            let horizonY = s * 0.66
            let sunR = s * 0.215
            let cx = s / 2

            ZStack {
                if showGlow {
                    Circle()
                        .fill(OrtusTheme.dawnGlow)
                        .frame(width: s * 0.95, height: s * 0.95)
                        .position(x: cx, y: horizonY)
                        .blur(radius: s * 0.04)
                }

                shape(s: s, stroke: stroke, horizonY: horizonY, sunR: sunR, cx: cx)
                    .foregroundStyle(paint)
            }
            .frame(width: s, height: s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var paint: AnyShapeStyle {
        switch fill {
        case .solid(let c): AnyShapeStyle(c)
        case .dawn: AnyShapeStyle(OrtusTheme.dawnGradient)
        }
    }

    private func shape(s: CGFloat, stroke: CGFloat, horizonY: CGFloat, sunR: CGFloat, cx: CGFloat) -> some View {
        ZStack {
            // Half-sun (filled semicircle sitting on the horizon)
            SunDome(horizonY: horizonY, sunR: sunR, cx: cx)

            // Horizon line with a gap where the sun sits
            HorizonLine(horizonY: horizonY, sunR: sunR, cx: cx, side: s, stroke: stroke)

            // Rays
            Rays(horizonY: horizonY, sunR: sunR, cx: cx, stroke: stroke)
        }
    }

    private struct SunDome: View {
        let horizonY, sunR, cx: CGFloat
        var body: some View {
            Path { p in
                p.addArc(center: CGPoint(x: cx, y: horizonY), radius: sunR,
                         startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                p.closeSubpath()
            }
        }
    }

    private struct HorizonLine: View {
        let horizonY, sunR, cx, side, stroke: CGFloat
        var body: some View {
            let inset = side * 0.10
            let gap = sunR * 1.45
            Path { p in
                p.move(to: CGPoint(x: inset, y: horizonY))
                p.addLine(to: CGPoint(x: cx - gap, y: horizonY))
                p.move(to: CGPoint(x: cx + gap, y: horizonY))
                p.addLine(to: CGPoint(x: side - inset, y: horizonY))
            }
            .stroke(style: StrokeStyle(lineWidth: stroke, lineCap: .round))
        }
    }

    private struct Rays: View {
        let horizonY, sunR, cx, stroke: CGFloat
        var body: some View {
            let angles: [Double] = [-90, -126, -54, -158, -22]
            let lens:   [CGFloat] = [0.95, 0.78, 0.78, 0.58, 0.58]
            Path { p in
                for (i, a) in angles.enumerated() {
                    let rad = a * .pi / 180
                    let start = sunR + sunR * 0.32
                    let end = start + sunR * lens[i]
                    p.move(to: CGPoint(x: cx + start * cos(rad), y: horizonY + start * sin(rad)))
                    p.addLine(to: CGPoint(x: cx + end * cos(rad), y: horizonY + end * sin(rad)))
                }
            }
            .stroke(style: StrokeStyle(lineWidth: stroke, lineCap: .round))
        }
    }
}

// MARK: - Card (lifted surface, e1)

struct OrtusCardModifier: ViewModifier {
    var tinted: Color? = nil
    var raised: Bool = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: OrtusTheme.radiusLG, style: .continuous)
        let base = content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OrtusTheme.spacingMD)
            .background(shape.fill(raised ? OrtusTheme.cardRaised : OrtusTheme.cardSurface))
            .background(shape.fill((tinted ?? .clear).opacity(0.10)))
            .overlay(shape.strokeBorder(OrtusTheme.hairline, lineWidth: 1))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [OrtusTheme.innerHighlight, .clear],
                                   startPoint: .top, endPoint: .center),
                    lineWidth: 1
                )
            )
            .clipShape(shape)
        return OrtusTheme.Elevation.e1(base)
    }
}

extension View {
    func ortusCard() -> some View { modifier(OrtusCardModifier()) }
    func ortusCard(tint: Color) -> some View { modifier(OrtusCardModifier(tinted: tint)) }
    func ortusCard(raised: Bool) -> some View { modifier(OrtusCardModifier(raised: raised)) }
}

// MARK: - Primary Button (warm "first light" CTA)

struct OrtusPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let active = (isHovering || pressed) && isEnabled
        return configuration.label
            .font(OrtusTheme.Typo.buttonPrimary)
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Capsule().fill(active ? OrtusTheme.accentHover : OrtusTheme.accent))
            .overlay(Capsule().strokeBorder(OrtusTheme.innerHighlightStrong, lineWidth: 1))
            .clipShape(Capsule())
            .opacity(isEnabled ? 1 : 0.45)
            .shadow(color: OrtusTheme.accent.opacity(isEnabled ? (active ? 0.50 : 0.32) : 0),
                    radius: active ? 16 : 9, y: active ? 5 : 3)
            .scaleEffect(pressed ? 0.965 : 1.0)
            .animation(OrtusTheme.Motion.press, value: pressed)
            .animation(OrtusTheme.Motion.hover, value: isHovering)
            .onHover { isHovering = $0 }
    }
}

// MARK: - Secondary Button (glass capsule)

struct OrtusSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let active = (isHovering || pressed) && isEnabled
        return configuration.label
            .font(OrtusTheme.Typo.button)
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Capsule().fill(OrtusTheme.cardSurface))
            .background(Capsule().fill(active ? Color.primary.opacity(0.06) : .clear))
            .overlay(Capsule().strokeBorder(active ? OrtusTheme.accent.opacity(0.4) : OrtusTheme.hairline, lineWidth: 1))
            .clipShape(Capsule())
            .opacity(isEnabled ? 1 : 0.5)
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            .scaleEffect(pressed ? 0.965 : 1.0)
            .animation(OrtusTheme.Motion.press, value: pressed)
            .animation(OrtusTheme.Motion.hover, value: isHovering)
            .onHover { isHovering = $0 }
    }
}

// MARK: - Destructive Button (ember-tinted capsule)

struct OrtusDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let active = (isHovering || pressed) && isEnabled
        return configuration.label
            .font(OrtusTheme.Typo.button)
            .foregroundStyle(isEnabled ? OrtusTheme.danger : OrtusTheme.danger.opacity(0.45))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Capsule().fill(OrtusTheme.danger.opacity(active ? 0.20 : 0.11)))
            .overlay(Capsule().strokeBorder(
                OrtusTheme.danger.opacity(isEnabled ? (active ? 0.62 : 0.38) : 0.18), lineWidth: 1))
            .clipShape(Capsule())
            .scaleEffect(pressed ? 0.965 : 1.0)
            .animation(OrtusTheme.Motion.press, value: pressed)
            .animation(OrtusTheme.Motion.hover, value: isHovering)
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
            .font(OrtusTheme.Typo.button)
            .foregroundStyle(active ? .primary : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(active ? Color.primary.opacity(0.06) : .clear))
            .clipShape(Capsule())
            .scaleEffect(pressed ? 0.965 : 1.0)
            .animation(OrtusTheme.Motion.press, value: pressed)
            .animation(OrtusTheme.Motion.hover, value: isHovering)
            .onHover { isHovering = $0 }
    }
}

// MARK: - Text Field (recessed input with focus glow)

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
            .overlay(shape.strokeBorder(isFocused ? OrtusTheme.accent : OrtusTheme.hairline,
                                        lineWidth: isFocused ? 1.5 : 1))
            .clipShape(shape)
            .shadow(color: isFocused ? OrtusTheme.accent.opacity(0.28) : .clear, radius: 5)
            .animation(OrtusTheme.Motion.hover, value: isFocused)
    }
}

// MARK: - Empty State

struct OrtusEmptyState: View {
    let icon: String
    let title: String
    let message: String
    /// When true, the brand sunmark is shown instead of an SF Symbol.
    var useSunmark: Bool = false

    var body: some View {
        VStack(spacing: OrtusTheme.spacingMD) {
            Spacer()
            if useSunmark {
                OrtusSunmark(showGlow: true)
                    .frame(width: 76, height: 76)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(OrtusTheme.accent.opacity(0.85))
                    .symbolRenderingMode(.hierarchical)
            }
            Text(title).font(OrtusTheme.Typo.title)
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

// MARK: - Section Header

struct OrtusSectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(OrtusTheme.Typo.section)
            .tracking(1.6)
            .foregroundStyle(OrtusTheme.textMuted)
    }
}

// MARK: - Popover background ("dawn sky" wash)

/// Solid adaptive canvas with a vertical sky gradient (deeper at top, lighter at
/// the horizon) plus a soft warm glow — "first light on the horizon." Avoids
/// NSVisualEffectView so the colour never shifts with the desktop wallpaper.
struct VibrantBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [OrtusTheme.canvas, OrtusTheme.canvasDeep],
                startPoint: .top, endPoint: .bottom
            )
            // First light, top-center.
            RadialGradient(
                colors: [OrtusTheme.accentSoft.opacity(0.9), OrtusTheme.accentSoft.opacity(0.25), .clear],
                center: .init(x: 0.5, y: -0.05), startRadius: 0, endRadius: 320
            )
        }
        .ignoresSafeArea()
    }
}
