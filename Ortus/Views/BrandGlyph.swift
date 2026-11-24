import SwiftUI
import OrtusCore

/// Monochrome, logo-like marks for the sites and apps Ortus can block. Built from
/// plain SwiftUI shapes in the current foreground colour (Canvas does not draw
/// inside the menu bar panel). The browser extension uses SVG versions of the same
/// marks (BrowserExtension/glyphs.js); keep the two in step.
struct BrandGlyph: View {
    let id: String
    var size: CGFloat = 16
    /// Text colour by default; the blocked-app stack draws marks in its ground colour.
    var color: Color = OrtusTheme.text

    var body: some View {
        let parts = Self.parts(for: id)
        ZStack {
            if parts.isEmpty { OrtusIcon(.globe, size: size) }
            ForEach(parts.indices, id: \.self) { index in render(parts[index]) }
        }
        .foregroundStyle(color)
        .frame(width: size, height: size)
        .compositingGroup()
        .accessibilityHidden(true)
    }

    @ViewBuilder private func render(_ part: Part) -> some View {
        let shape = UnitShape(path: part.path)
        let style = StrokeStyle(lineWidth: part.width * size, lineCap: .round, lineJoin: .round)
        switch (part.width > 0, part.cut) {
        case (false, false): shape.fill()
        case (true, false): shape.stroke(style: style)
        case (false, true): shape.fill().blendMode(.destinationOut)
        case (true, true): shape.stroke(style: style).blendMode(.destinationOut)
        }
    }

    /// A path in a 0…1 square; `width` > 0 strokes it, `cut` punches it out of the mark.
    private struct Part { var path: Path; var width: CGFloat = 0; var cut = false }

    private struct UnitShape: Shape {
        let path: Path
        func path(in rect: CGRect) -> Path { path.applying(CGAffineTransform(scaleX: rect.width, y: rect.height)) }
    }

    private static func lines(_ points: [(CGFloat, CGFloat)]) -> Path {
        var path = Path(); path.addLines(points.map { CGPoint(x: $0.0, y: $0.1) }); return path
    }
    private static func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
        var path = lines(points); path.closeSubpath(); return path
    }
    private static func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r, style: .continuous)
    }
    private static func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }

    private static let websiteIDs = [
        "youtube.com": "youtube", "youtu.be": "youtube", "twitch.tv": "twitch",
        "netflix.com": "netflix", "spotify.com": "spotify", "discord.com": "discord",
        "discord.gg": "discord", "telegram.org": "telegram", "t.me": "telegram",
    ]

    static func websiteID(for domain: String) -> String? {
        if let preset = BlockingPreset.all.first(where: { preset in
            preset.selection.websites.contains { WebsiteDomain.matches(host: domain, domain: $0) }
        }) { return preset.id }
        return websiteIDs.first { WebsiteDomain.matches(host: domain, domain: $0.key) }?.value
    }

    static func applicationID(for app: BlockedApplication) -> String? {
        if let preset = BlockingPreset.all.first(where: { $0.selection.applications.contains { $0.id == app.id } }) { return preset.id }
        switch app.bundleID {
        case "com.spotify.client": return "spotify"
        case "com.hnc.Discord": return "discord"
        case "ru.keepcoder.Telegram", "com.tdesktop.Telegram": return "telegram"
        default: return nil
        }
    }

    private static func parts(for id: String) -> [Part] {
        switch id {
        case "gmail":
            return [Part(path: rounded(0.08, 0.2, 0.84, 0.62, 0.12), width: 0.09),
                    Part(path: lines([(0.14, 0.28), (0.5, 0.56), (0.86, 0.28)]), width: 0.09)]
        case "slack":
            // Rounded hash, like Slack's mark. Avoid rotated-hook arrangements.
            return [rounded(0.25, 0.06, 0.19, 0.88, 0.095), rounded(0.56, 0.06, 0.19, 0.88, 0.095),
                    rounded(0.06, 0.25, 0.88, 0.19, 0.095), rounded(0.06, 0.56, 0.88, 0.19, 0.095)].map { Part(path: $0) }
        case "linkedin":
            var arch = Path()
            arch.move(to: CGPoint(x: 0.5, y: 0.58))
            arch.addQuadCurve(to: CGPoint(x: 0.72, y: 0.58), control: CGPoint(x: 0.6, y: 0.42))
            arch.addLine(to: CGPoint(x: 0.72, y: 0.76))
            return [Part(path: rounded(0.06, 0.06, 0.88, 0.88, 0.2)),
                    Part(path: circle(0.3, 0.29, 0.075), cut: true),
                    Part(path: lines([(0.3, 0.45), (0.3, 0.76)]), width: 0.13, cut: true),
                    Part(path: lines([(0.5, 0.76), (0.5, 0.45)]), width: 0.12, cut: true),
                    Part(path: arch, width: 0.12, cut: true)]
        case "x":
            return [Part(path: lines([(0.16, 0.12), (0.84, 0.88)]), width: 0.16),
                    Part(path: lines([(0.84, 0.12), (0.16, 0.88)]), width: 0.07)]
        case "instagram":
            return [Part(path: rounded(0.1, 0.1, 0.8, 0.8, 0.24), width: 0.09),
                    Part(path: circle(0.5, 0.5, 0.18), width: 0.09),
                    Part(path: circle(0.71, 0.29, 0.055))]
        case "facebook":
            var f = Path()
            f.move(to: CGPoint(x: 0.56, y: 0.94))
            f.addLine(to: CGPoint(x: 0.56, y: 0.42))
            f.addQuadCurve(to: CGPoint(x: 0.72, y: 0.26), control: CGPoint(x: 0.56, y: 0.26))
            return [Part(path: circle(0.5, 0.5, 0.44)),
                    Part(path: f, width: 0.13, cut: true),
                    Part(path: lines([(0.42, 0.53), (0.7, 0.53)]), width: 0.11, cut: true)]
        case "reddit":
            return [Part(path: Path(ellipseIn: CGRect(x: 0.1, y: 0.34, width: 0.8, height: 0.56))),
                    Part(path: circle(0.76, 0.14, 0.08)),
                    Part(path: lines([(0.5, 0.36), (0.56, 0.12), (0.72, 0.15)]), width: 0.06),
                    Part(path: circle(0.36, 0.58, 0.07), cut: true),
                    Part(path: circle(0.64, 0.58, 0.07), cut: true)]
        case "tiktok":
            var tail = Path()
            tail.move(to: CGPoint(x: 0.53, y: 0.12))
            tail.addQuadCurve(to: CGPoint(x: 0.84, y: 0.36), control: CGPoint(x: 0.6, y: 0.34))
            return [Part(path: circle(0.36, 0.72, 0.18)),
                    Part(path: lines([(0.53, 0.72), (0.53, 0.1)]), width: 0.13),
                    Part(path: tail, width: 0.11)]
        case "whatsapp":
            var bubble = Path(ellipseIn: CGRect(x: 0.12, y: 0.08, width: 0.8, height: 0.8))
            bubble.move(to: CGPoint(x: 0.2, y: 0.7))
            bubble.addLine(to: CGPoint(x: 0.08, y: 0.94))
            bubble.addLine(to: CGPoint(x: 0.34, y: 0.84))
            var handset = Path()
            handset.move(to: CGPoint(x: 0.38, y: 0.32))
            handset.addQuadCurve(to: CGPoint(x: 0.66, y: 0.62), control: CGPoint(x: 0.38, y: 0.6))
            return [Part(path: bubble, width: 0.08), Part(path: handset, width: 0.12)]
        case "youtube":
            return [Part(path: rounded(0.06, 0.2, 0.88, 0.6, 0.18)),
                    Part(path: polygon([(0.42, 0.34), (0.7, 0.5), (0.42, 0.66)]), cut: true)]
        case "twitch":
            return [Part(path: polygon([(0.14, 0.06), (0.94, 0.06), (0.94, 0.64), (0.7, 0.88), (0.5, 0.88), (0.34, 1), (0.34, 0.88), (0.14, 0.88)])),
                    Part(path: polygon([(0.26, 0.18), (0.82, 0.18), (0.82, 0.56), (0.65, 0.73), (0.48, 0.73), (0.36, 0.84), (0.36, 0.73), (0.26, 0.73)]), cut: true),
                    Part(path: rounded(0.42, 0.3, 0.095, 0.25, 0)), Part(path: rounded(0.64, 0.3, 0.095, 0.25, 0))]
        case "netflix":
            return [Part(path: rounded(0.18, 0.06, 0.18, 0.88, 0)), Part(path: rounded(0.64, 0.06, 0.18, 0.88, 0)),
                    Part(path: polygon([(0.18, 0.06), (0.39, 0.06), (0.82, 0.94), (0.61, 0.94)]))]
        case "spotify":
            var top = Path(); top.move(to: CGPoint(x: 0.25, y: 0.36)); top.addQuadCurve(to: CGPoint(x: 0.78, y: 0.39), control: CGPoint(x: 0.52, y: 0.23))
            var middle = Path(); middle.move(to: CGPoint(x: 0.28, y: 0.51)); middle.addQuadCurve(to: CGPoint(x: 0.74, y: 0.54), control: CGPoint(x: 0.5, y: 0.4))
            var bottom = Path(); bottom.move(to: CGPoint(x: 0.31, y: 0.65)); bottom.addQuadCurve(to: CGPoint(x: 0.69, y: 0.68), control: CGPoint(x: 0.5, y: 0.56))
            return [Part(path: circle(0.5, 0.5, 0.44)), Part(path: top, width: 0.08, cut: true),
                    Part(path: middle, width: 0.07, cut: true), Part(path: bottom, width: 0.06, cut: true)]
        case "discord":
            var controller = Path()
            controller.move(to: CGPoint(x: 0.29, y: 0.19))
            for point in [CGPoint(x: 0.41, y: 0.16), CGPoint(x: 0.44, y: 0.22), CGPoint(x: 0.56, y: 0.22), CGPoint(x: 0.59, y: 0.16), CGPoint(x: 0.71, y: 0.19)] { controller.addLine(to: point) }
            controller.addCurve(to: CGPoint(x: 0.9, y: 0.75), control1: CGPoint(x: 0.82, y: 0.37), control2: CGPoint(x: 0.9, y: 0.59))
            controller.addQuadCurve(to: CGPoint(x: 0.72, y: 0.84), control: CGPoint(x: 0.84, y: 0.81))
            for point in [CGPoint(x: 0.68, y: 0.77), CGPoint(x: 0.32, y: 0.77), CGPoint(x: 0.28, y: 0.84)] { controller.addLine(to: point) }
            controller.addQuadCurve(to: CGPoint(x: 0.1, y: 0.75), control: CGPoint(x: 0.16, y: 0.81))
            controller.addCurve(to: CGPoint(x: 0.29, y: 0.19), control1: CGPoint(x: 0.1, y: 0.59), control2: CGPoint(x: 0.18, y: 0.37))
            controller.closeSubpath()
            return [Part(path: controller), Part(path: circle(0.36, 0.52, 0.07), cut: true), Part(path: circle(0.64, 0.52, 0.07), cut: true)]
        case "telegram":
            return [Part(path: circle(0.5, 0.5, 0.44)),
                    Part(path: polygon([(0.2, 0.46), (0.8, 0.22), (0.68, 0.78), (0.5, 0.6), (0.4, 0.7), (0.4, 0.53)]), cut: true),
                    Part(path: lines([(0.41, 0.53), (0.69, 0.33)]), width: 0.04)]
        default:
            return []
        }
    }
}

/// What a mode blocks, as items: one per preset it holds (Gmail, Slack), then one per
/// other website or app, sorted by name.
struct BlockedItem: Identifiable, Equatable {
    let id: String
    let glyph: String
    let name: String
    let isApp: Bool

    @MainActor static func all(in selection: BlockSelection) -> [BlockedItem] {
        var items: [BlockedItem] = []
        var websites = selection.websites
        var apps = selection.applications
        for preset in BlockingPreset.all where selection.contains(preset) {
            let name = preset.id == "slack" && !selection.fullyContains(preset)
                ? (selection.blocksSlack ? "Slack app" : "Slack website") : preset.title
            items.append(BlockedItem(id: preset.id, glyph: preset.id, name: name, isApp: preset.selection.websites.isEmpty))
            websites.removeAll { preset.selection.websites.contains($0) }
            apps.removeAll { app in preset.selection.applications.contains { $0.id == app.id } }
        }
        items += websites.map { BlockedItem(id: $0, glyph: BrandGlyph.websiteID(for: $0) ?? "", name: $0, isApp: false) }
        items += apps.map { BlockedItem(id: $0.id, glyph: BrandGlyph.applicationID(for: $0) ?? "", name: $0.name, isApp: true) }
        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// "6 sites", "2 apps", "3 sites · 2 apps": a count instead of a list of names.
    @MainActor static func countLabel(for selection: BlockSelection) -> String {
        let items = all(in: selection)
        let sites = items.filter { !$0.isApp }.count
        let apps = selection.applications.count
        func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        switch (sites, apps) {
        case (0, 0): return "Nothing yet"
        case (_, 0): return plural(sites, "site")
        case (0, _): return plural(apps, "app")
        default: return plural(sites, "site") + " · " + plural(apps, "app")
        }
    }
}

/// Blocked apps and sites: overlapping circles that fade a step each, each holding its
/// mark in the ground colour, the most opaque on top. After `limit` marks, a +N count.
struct BlockedStack: View {
    let items: [BlockedItem]
    /// What the stack sits on: draws the ring between circles and the marks.
    var ground: Color = OrtusTheme.cardSurface
    var size: CGFloat = 26
    var limit = 3
    var showsMore = true

    @Environment(\.colorScheme) private var scheme

    /// Solid fills from the strongest (front) to the faintest (back). Opaque, so a circle
    /// never shows the one behind it, and every fill keeps the mark readable: ink to
    /// bone-muted under bone marks when free, bone to stone under ink marks when locked.
    static func fill(index: Int, locked: Bool) -> Color {
        let from: UInt32 = locked ? 0xF2EEE8 : 0x1C1C19
        let to: UInt32 = locked ? 0x9A978E : 0x5E5C55
        let t = min(Double(index) / 5, 1)
        func channel(_ value: UInt32, _ shift: UInt32) -> Double { Double((value >> shift) & 0xFF) }
        let mixed = [16, 8, 0].reduce(UInt32(0)) { result, shift in
            let c = channel(from, UInt32(shift)) + (channel(to, UInt32(shift)) - channel(from, UInt32(shift))) * t
            return result | (UInt32(c.rounded()) << UInt32(shift))
        }
        return Color(hex: mixed)
    }

    var body: some View {
        let shown = Array(items.prefix(limit))
        HStack(spacing: 8) {
            HStack(spacing: -8) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                    mark(item)
                        .frame(width: size, height: size)
                        .background(Circle().fill(Self.fill(index: index, locked: scheme == .dark)))
                        .overlay(Circle().strokeBorder(ground, lineWidth: 2))
                        .zIndex(Double(shown.count - index))
                }
            }
            if showsMore, items.count > limit {
                Text("+\(items.count - limit)")
                    .font(OrtusTheme.Typo.badge).monospacedDigit()
                    .fixedSize()
                    .foregroundStyle(OrtusTheme.text)
                    .padding(.horizontal, 8)
                    .frame(height: size - 4)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(OrtusTheme.cardChip))
            }
        }
        .help(items.map(\.name).joined(separator: ", "))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Blocks " + items.map(\.name).joined(separator: ", "))
    }

    @ViewBuilder private func mark(_ item: BlockedItem) -> some View {
        if item.glyph.isEmpty && item.isApp {
            OrtusIcon(.app, size: size * 0.48).foregroundStyle(ground)
        } else {
            BrandGlyph(id: item.glyph, size: size * 0.5, color: ground)
        }
    }
}

/// Up to three marks that summarise a mode in a list: small sand circles, overlapping.
struct ModeGlyphs: View {
    let selection: BlockSelection

    static func identifiers(for selection: BlockSelection) -> [String] {
        let presets = BlockingPreset.all.filter { selection.fullyContains($0) }.map(\.id)
        let websites = selection.websites.compactMap { BrandGlyph.websiteID(for: $0) }
        let applications = selection.applications.compactMap { BrandGlyph.applicationID(for: $0) }
        var seen = Set<String>()
        return Array((presets + websites + applications).filter { seen.insert($0).inserted }.prefix(3))
    }

    var body: some View {
        let ids = Self.identifiers(for: selection)
        HStack(spacing: -4) {
            if ids.isEmpty {
                OrtusIcon(.blocked, size: 12).frame(width: 22, height: 22)
                    .background(Circle().fill(OrtusTheme.fill))
            }
            ForEach(ids, id: \.self) { id in
                BrandGlyph(id: id, size: 12)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(OrtusTheme.fill))
            }
        }
    }
}
