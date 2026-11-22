import AppKit
import CoreText
import SwiftUI

// MARK: - Design System: First Light
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │  ORTUS VISUAL RULES (brand kit: brain/projects/ortus/brand/)         │
// │  The browser extension (BrowserExtension/style.css) and the website  │
// │  (landing/styles.css) use the same tokens. Change all three.         │
// │                                                                      │
// │  1. BONE IS FREE, INK IS LOCKED. The panel ignores macOS dark mode.  │
// │     ContentView sets colorScheme .light when free and .dark during   │
// │     a session, so every token below resolves to bone or ink. Never   │
// │     read the system appearance.                                      │
// │                                                                      │
// │  2. ORANGE IS RARE. Persimmon marks the sun, the locked state and at │
// │     most one action per screen. Never text on bone (2.4:1).          │
// │     Problems use the persimmon warning triangle (OrtusProblemIcon).  │
// │                                                                      │
// │  3. ONE TYPE FAMILY. Archivo Black (OrtusFont.display) for big words │
// │     and numbers, 28 pt and up. Archivo for everything else, buttons  │
// │     in 700. Never Archivo Black in a button.                         │
// │                                                                      │
// │  4. SQUIRCLES FOR WHAT YOU TOUCH, STRAIGHT LINES FOR STRUCTURE.      │
// │     Buttons and tiles 12, cards 18. Dividers and progress bars are   │
// │     straight, square-ended lines. No shadows, glows or gradients.    │
// │                                                                      │
// │  5. ROWS: OrtusListRow inside an OrtusGroup, full-width lines        │
// │     between rows. BUTTONS: OrtusPrimaryButtonStyle (one per view),   │
// │     OrtusSecondaryButtonStyle, OrtusRowButtonStyle (2 pt outline),   │
// │     OrtusGhostButtonStyle (underlined text).                         │
// │                                                                      │
// │  6. ICONS: OrtusIcon, solid shapes with real cut-outs, 24 grid.      │
// │     Inactive icons take the muted colour.                            │
// │                                                                      │
// │  7. VOICE: stoic, blunt, short. "Lock in" is the verb. No cheering,  │
// │     no exclamation marks, no "AI" (say "agent").                     │
// └─────────────────────────────────────────────────────────────────────┘

enum OrtusTheme {
    // MARK: Brand colours (fixed)

    static let bone = Color(hex: 0xF2EEE8)
    static let ink = Color(hex: 0x1C1C19)
    static let sand = Color(hex: 0xE3DED5)
    static let ash = Color(hex: 0x2E2D29)
    static let stone = Color(hex: 0x9A978E)
    static let boneMuted = Color(hex: 0x5E5C55)
    static let lineOnInk = Color(hex: 0x3A3934)
    static let persimmon = Color(hex: 0xFE701C)
    static let white = Color.white

    // MARK: Roles (free / locked)

    /// The panel ground: bone when free, ink when locked.
    static let canvas = dynamic(free: 0xF2EEE8, locked: 0x1C1C19)
    /// Cards and modal sheets: white on bone, ash on ink.
    static let cardSurface = dynamic(free: 0xFFFFFF, locked: 0x2E2D29)
    /// Secondary buttons, chips, fields and the tab bar: sand on bone, ash on ink.
    static let fill = dynamic(free: 0xE3DED5, locked: 0x2E2D29)
    /// A box inside a card: bone inside white, ink inside ash.
    static let inset = dynamic(free: 0xF2EEE8, locked: 0x1C1C19)
    /// Chips and avatars inside a card: sand in white, ink in ash.
    static let cardChip = dynamic(free: 0xE3DED5, locked: 0x1C1C19)
    /// Dividers and progress tracks.
    static let line = dynamic(free: 0xE3DED5, locked: 0x3A3934)
    /// Text and icons.
    static let text = dynamic(free: 0x1C1C19, locked: 0xF2EEE8)
    /// Muted text and inactive icons: bone muted on bone, stone on ink.
    static let textMuted = dynamic(free: 0x5E5C55, locked: 0x9A978E)
    /// The primary button and selected states: ink on bone, bone on ink.
    static let strong = dynamic(free: 0x1C1C19, locked: 0xF2EEE8)
    /// Text and icons on `strong`.
    static let onStrong = dynamic(free: 0xF2EEE8, locked: 0x1C1C19)
    /// The sun, the locked state, one action per screen.
    static let accent = persimmon
    /// Text on persimmon.
    static let onAccent = ink
    /// The dim behind a modal.
    static let scrim = dynamic(free: 0x1C1C19, locked: 0x1C1C19, freeAlpha: 0.42, lockedAlpha: 0.55)

    /// Resolves through the SwiftUI colour scheme, which ContentView pins to the lock state.
    private static func dynamic(free: UInt32, locked: UInt32, freeAlpha: CGFloat = 1, lockedAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(hex: locked, alpha: lockedAlpha) : NSColor(hex: free, alpha: freeAlpha)
        })
    }

    // MARK: Spacing (4 pt grid)

    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 16
    static let spacingLG: CGFloat = 22
    static let spacingXL: CGFloat = 32

    /// Button heights: small (row actions), medium, large (the one primary).
    static let controlHeightSM: CGFloat = 34
    static let controlHeight: CGFloat = 44
    static let controlHeightLG: CGFloat = 52

    // MARK: Corner radii (continuous)

    static let radiusSM: CGFloat = 8
    static let radiusMD: CGFloat = 12
    static let radiusLG: CGFloat = 18
    static let radiusXL: CGFloat = 22

    // MARK: Type scale
    //
    // The only type tokens a view should use.

    enum Typo {
        /// The session timer.
        static let hero = OrtusFont.display(104)
        /// The grace countdown.
        static let countdown = OrtusFont.display(120)
        /// Big numbers inside cards ("90 min", a verification code).
        static let display = OrtusFont.display(34)
        /// Screen headings ("Ready when you are").
        static let title = OrtusFont.display(34)
        /// Secondary screen headings ("Ask your agent.").
        static let titleSmall = OrtusFont.display(30)
        /// Modal titles that make a statement ("No end button.").
        static let sheetTitle = OrtusFont.display(26)
        /// Modal titles for setup forms ("Connect Slack").
        static let sheetTitleSmall = OrtusFont.text(19, .bold)
        /// Card titles ("Focus Time").
        static let cardTitle = OrtusFont.text(17, .bold)
        /// Row titles and emphasis.
        static let headline = OrtusFont.text(15, .semibold)
        /// Running text: paragraphs, chat answers.
        static let body = OrtusFont.text(15)
        /// Body that needs more weight.
        static let bodyMedium = OrtusFont.text(15, .medium)
        /// Smaller paragraphs in modals.
        static let callout = OrtusFont.text(14)
        /// Status lines under titles.
        static let caption = OrtusFont.text(13)
        /// Small metadata.
        static let meta = OrtusFont.text(12)
        /// Uppercase labels. Use with .tracking(1.3).
        static let section = OrtusFont.text(11, .bold)
        /// Small badges and counts.
        static let badge = OrtusFont.text(12, .bold)
        /// Medium buttons.
        static let button = OrtusFont.text(15, .bold)
        /// Small buttons.
        static let buttonSmall = OrtusFont.text(13, .bold)
        /// The large primary button.
        static let buttonPrimary = OrtusFont.text(17, .bold)
    }
}

// MARK: - Fonts

/// Archivo and Archivo Black, bundled in Contents/Resources/Fonts (copied by build.sh).
/// Without the bundle (a bare `swift run`), SwiftUI falls back to the system font.
enum OrtusFont {
    enum Weight { case regular, medium, semibold, bold, extraBold }

    /// Call once at launch, before any view draws.
    static func register() {
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("Fonts", isDirectory: true),
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for url in files where ["woff2", "ttf", "otf"].contains(url.pathExtension) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static let displayName = "ArchivoBlack-Regular"

    /// The named instances of the Archivo variable font.
    static func name(_ weight: Weight) -> String {
        switch weight {
        case .regular: "ArchivoRoman-Regular"
        case .medium: "ArchivoRoman-Medium"
        case .semibold: "ArchivoSemiBold-Regular"
        case .bold: "ArchivoRoman-Bold"
        case .extraBold: "ArchivoRoman-ExtraBold"
        }
    }

    static func display(_ size: CGFloat) -> Font { .custom(displayName, fixedSize: size) }
    static func text(_ size: CGFloat, _ weight: Weight = .regular) -> Font { .custom(name(weight), fixedSize: size) }

    /// For AppKit text views.
    static func nsText(_ size: CGFloat, _ weight: Weight = .regular) -> NSFont {
        NSFont(name: name(weight), size: size) ?? .systemFont(ofSize: size, weight: weight == .regular ? .regular : weight == .medium ? .medium : .bold)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

// MARK: - On a card

private struct OnCardKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// True inside a card or sheet. Fills that are ash on the ink ground (secondary
    /// buttons, fields, switch tracks) turn ink there, so they don't vanish into the ash card.
    var ortusOnCard: Bool {
        get { self[OnCardKey.self] }
        set { self[OnCardKey.self] = newValue }
    }
}

extension OrtusTheme {
    /// Secondary buttons, fields and switch tracks: `fill` on the ground, `cardChip` on a card.
    static func controlFill(onCard: Bool) -> Color { onCard ? cardChip : fill }
}

// MARK: - Free / locked

extension View {
    /// Pins the panel to bone (free) or ink (locked), whatever macOS is set to. Also sets
    /// the hosting window's appearance, so AppKit controls inside (text fields, text
    /// views, scrollers) resolve the same colours.
    func ortusLockAppearance(locked: Bool) -> some View {
        environment(\.colorScheme, locked ? .dark : .light)
            .background(WindowAppearance(locked: locked))
    }
}

private struct WindowAppearance: NSViewRepresentable {
    let locked: Bool

    final class Probe: NSView {
        var appearanceName: NSAppearance.Name = .aqua {
            didSet { apply() }
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }
        private func apply() {
            guard let window, window.appearance?.name != appearanceName else { return }
            window.appearance = NSAppearance(named: appearanceName)
        }
    }

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) {
        view.appearanceName = locked ? .darkAqua : .aqua
    }
}

// MARK: - Card

struct OrtusCardModifier: ViewModifier {
    var padding: CGFloat = OrtusTheme.spacingMD
    func body(content: Content) -> some View {
        content
            .environment(\.ortusOnCard, true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: OrtusTheme.radiusLG, style: .continuous).fill(OrtusTheme.cardSurface))
    }
}

extension View {
    func ortusCard(padding: CGFloat = OrtusTheme.spacingMD) -> some View {
        modifier(OrtusCardModifier(padding: padding))
    }
}

// MARK: - Buttons

enum OrtusButtonSize {
    case small, medium, large
    var height: CGFloat { switch self { case .small: OrtusTheme.controlHeightSM; case .medium: OrtusTheme.controlHeight; case .large: OrtusTheme.controlHeightLG } }
    var padding: CGFloat { switch self { case .small: 12; case .medium: 18; case .large: 24 } }
    var font: Font { switch self { case .small: OrtusTheme.Typo.buttonSmall; case .medium: OrtusTheme.Typo.button; case .large: OrtusTheme.Typo.buttonPrimary } }
}

/// The squircle every button shares; the styles below only pick its colours.
private struct OrtusButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let size: OrtusButtonSize
    let background: Color
    let foreground: Color
    var outline: Color? = nil
    var sun = false
    var fullWidth = false
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous)
        HStack(spacing: 9) {
            if sun { OrtusMark(width: size == .large ? 20 : 16, color: OrtusTheme.accent) }
            configuration.label
        }
        .frame(maxWidth: fullWidth ? .infinity : nil)
        .font(size.font)
        .lineLimit(1)
        .foregroundStyle(foreground)
        .padding(.horizontal, size.padding)
        .frame(minHeight: size.height)
        .background(shape.fill(background))
        .overlay { if let outline { shape.strokeBorder(outline, lineWidth: 2) } }
        .contentShape(shape)
        .opacity(!isEnabled ? 0.35 : isHovering || configuration.isPressed ? 0.86 : 1)
        .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1)
        .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

/// The one primary action per screen: ink on bone, bone on ink. `sun` puts the
/// persimmon mark before the label ("Lock in · 90 min").
struct OrtusPrimaryButtonStyle: ButtonStyle {
    var size: OrtusButtonSize = .medium
    var sun = false
    var fullWidth = false
    func makeBody(configuration: Configuration) -> some View {
        OrtusButtonBody(configuration: configuration, size: size, background: OrtusTheme.strong, foreground: OrtusTheme.onStrong,
                        sun: sun, fullWidth: fullWidth)
    }
}

/// Sand on bone, ash on ink.
struct OrtusSecondaryButtonStyle: ButtonStyle {
    var size: OrtusButtonSize = .medium
    var fullWidth = false
    func makeBody(configuration: Configuration) -> some View {
        SecondaryBody(configuration: configuration, size: size, fullWidth: fullWidth)
    }

    private struct SecondaryBody: View {
        let configuration: ButtonStyleConfiguration
        let size: OrtusButtonSize
        let fullWidth: Bool
        @Environment(\.ortusOnCard) private var onCard
        var body: some View {
            OrtusButtonBody(configuration: configuration, size: size, background: OrtusTheme.controlFill(onCard: onCard),
                            foreground: OrtusTheme.text, fullWidth: fullWidth)
        }
    }
}

/// A row's trailing action: 2 pt outline in the text colour.
struct OrtusRowButtonStyle: ButtonStyle {
    var role: ButtonRole? = nil
    func makeBody(configuration: Configuration) -> some View {
        OrtusButtonBody(configuration: configuration, size: .small, background: .clear, foreground: OrtusTheme.text, outline: OrtusTheme.text)
    }
}

/// Text actions: underlined, in the text colour.
struct OrtusGhostButtonStyle: ButtonStyle {
    var size: OrtusButtonSize = .small
    func makeBody(configuration: Configuration) -> some View {
        GhostBody(configuration: configuration, size: size)
    }

    private struct GhostBody: View {
        let configuration: ButtonStyleConfiguration
        let size: OrtusButtonSize
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false
        var body: some View {
            configuration.label
                .font(size.font)
                .underline(true, pattern: .solid)
                .foregroundStyle(OrtusTheme.text)
                .padding(.horizontal, 6)
                .frame(minHeight: size == .small ? 28 : size.height)
                .contentShape(Rectangle())
                .opacity(!isEnabled ? 0.35 : isHovering || configuration.isPressed ? 0.7 : 1)
                .onHover { isHovering = $0 }
        }
    }
}

// MARK: - Toggle

/// A squircle switch: ink (bone) or persimmon (ink) when on, sand or ash when off.
struct OrtusToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        ToggleBody(configuration: configuration)
    }

    private struct ToggleBody: View {
        let configuration: ToggleStyleConfiguration
        @Environment(\.colorScheme) private var scheme
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.ortusOnCard) private var onCard
        var body: some View {
            let locked = scheme == .dark
            let on = configuration.isOn
            let track = on ? (locked ? OrtusTheme.accent : OrtusTheme.ink) : OrtusTheme.controlFill(onCard: onCard)
            let knob = on || locked ? OrtusTheme.bone : OrtusTheme.white
            Button { configuration.isOn.toggle() } label: {
                ZStack(alignment: on ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(track)
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(knob)
                        .frame(width: 19, height: 19).padding(3)
                }
                .frame(width: 42, height: 25)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.easeOut(duration: 0.15), value: on)
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(on ? "On" : "Off")
        }
    }
}

// MARK: - Text field

struct OrtusTextFieldStyle: TextFieldStyle {
    var monospaced = false
    @FocusState private var isFocused: Bool
    @Environment(\.ortusOnCard) private var onCard

    func _body(configuration: TextField<Self._Label>) -> some View {
        let shape = RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous)
        return configuration
            .textFieldStyle(.plain)
            .font(monospaced ? .system(size: 14, design: .monospaced) : OrtusFont.text(15, .medium))
            .foregroundStyle(OrtusTheme.text)
            .padding(.horizontal, 14)
            .frame(minHeight: OrtusTheme.controlHeight)
            .focused($isFocused)
            .background(shape.fill(OrtusTheme.controlFill(onCard: onCard)))
            .overlay(shape.strokeBorder(OrtusTheme.text.opacity(isFocused ? 1 : 0), lineWidth: 2))
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Empty state

struct OrtusEmptyState: View {
    let icon: OrtusIcon.Name
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: OrtusTheme.spacingMD) {
            Spacer()
            OrtusIcon(icon, size: 36).foregroundStyle(OrtusTheme.text)
            Text(title)
                .font(OrtusTheme.Typo.titleSmall)
                .tracking(-1)
                .multilineTextAlignment(.center)
            Text(message)
                .font(OrtusTheme.Typo.callout)
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

// MARK: - Panel background

/// The solid ground of the panel: bone or ink. No material, so the wallpaper never
/// tints it.
struct VibrantBackground: View {
    var body: some View {
        OrtusTheme.canvas.ignoresSafeArea()
    }
}

// MARK: - Section header

struct OrtusSectionHeader: View {
    let title: String
    var color: Color = OrtusTheme.textMuted

    var body: some View {
        Text(title.uppercased())
            .font(OrtusTheme.Typo.section)
            .tracking(1.3)
            .foregroundStyle(color)
    }
}

// MARK: - The line

/// A straight, square-ended progress bar: a persimmon bar over a thin track.
struct OrtusLineProgress: View {
    let fraction: Double
    var height: CGFloat = 12
    var trackHeight: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(OrtusTheme.line).frame(height: trackHeight)
                Rectangle().fill(OrtusTheme.accent)
                    .frame(width: max(0, min(1, fraction)) * proxy.size.width, height: height)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int((max(0, min(1, fraction)) * 100).rounded())) percent")
    }
}

// MARK: - Problem marker

/// A problem: the persimmon warning triangle with the bang cut out. Counts as the
/// screen's one orange.
struct OrtusProblemIcon: View {
    var size: CGFloat = 22
    var body: some View {
        OrtusIcon(.warn, size: size).foregroundStyle(OrtusTheme.accent).accessibilityLabel("Problem")
    }
}
