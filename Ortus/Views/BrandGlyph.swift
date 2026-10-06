import SwiftUI
import OrtusCore

/// Monochrome, logo-like marks for the sites and apps Ortus can block. Built from
/// plain SwiftUI shapes in the current foreground colour (Canvas does not draw
/// inside the menu bar panel). The browser extension uses SVG versions of the same
/// marks (BrowserExtension/glyphs.js); keep the two in step.
struct BrandGlyph: View {
    let id: String
    var size: CGFloat = 16

    var body: some View {
        let parts = Self.parts(for: id)
        ZStack {
            if parts.isEmpty { Image(systemName: "globe").resizable().scaledToFit() }
            ForEach(parts.indices, id: \.self) { index in render(parts[index]) }
        }
        .foregroundStyle(OrtusTheme.ink)
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
    private static func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r, style: .continuous)
    }
    private static func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
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
        default:
            return []
        }
    }
}

/// Up to three marks that summarise a mode. `cluster` arranges them as a small
/// floating triangle (used where the mode is the subject); otherwise they sit in a
/// compact overlapping row (used in lists).
struct ModeGlyphs: View {
    let selection: BlockSelection
    var cluster = false

    var body: some View {
        let ids = Array(BlockingPreset.all.filter { selection.fullyContains($0) }.map(\.id).prefix(3))
        Group {
            if ids.isEmpty {
                Image(systemName: "square.dashed").font(.system(size: 13)).frame(width: 22, height: 22)
            } else if cluster {
                ZStack {
                    ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                        FloatingMark(id: id, index: index).offset(Self.triangle(count: ids.count)[index])
                    }
                }
                .frame(width: 46, height: 40)
            } else {
                HStack(spacing: -4) {
                    ForEach(ids, id: \.self) { id in mark(id) }
                }
            }
        }
        .foregroundStyle(.primary)
    }

    /// Top mark sits behind; the lower two overlap in front of it.
    private static func triangle(count: Int) -> [CGSize] {
        switch count {
        case 1: [.zero]
        case 2: [CGSize(width: -9, height: 0), CGSize(width: 9, height: 0)]
        default: [CGSize(width: 0, height: -8), CGSize(width: -10, height: 7), CGSize(width: 10, height: 7)]
        }
    }

    fileprivate static func circle<Content: View>(_ content: Content) -> some View {
        content
            .frame(width: 22, height: 22)
            .background(Circle().fill(OrtusTheme.cardSurface))
            .overlay(Circle().strokeBorder(OrtusTheme.hairline, lineWidth: 1))
    }

    private func mark(_ id: String) -> some View { Self.circle(BrandGlyph(id: id, size: 12)) }
}

/// One mark of the cluster, drifting a point up and down on its own slow rhythm.
private struct FloatingMark: View {
    let id: String
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var raised = false

    var body: some View {
        ModeGlyphs.circle(BrandGlyph(id: id, size: 12))
            .shadow(color: .black.opacity(0.10), radius: 3, y: 2)
            .offset(y: raised ? -1.2 : 1.2)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.2 + Double(index) * 0.45).repeatForever(autoreverses: true).delay(Double(index) * 0.35)) {
                    raised = true
                }
            }
    }
}
