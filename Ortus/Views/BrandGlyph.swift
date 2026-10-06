import SwiftUI
import OrtusCore

/// Monochrome, logo-like marks for the sites and apps Ortus can block. Drawn from
/// simple shapes in the current foreground colour so they sit quietly next to text.
/// The browser extension uses SVG versions of the same marks (BrowserExtension/glyphs.js).
struct BrandGlyph: View {
    let id: String
    var size: CGFloat = 16

    var body: some View {
        Canvas { context, canvas in
            let s = canvas.width
            let ink = GraphicsContext.Shading.foreground
            func line(_ points: [CGPoint], width: CGFloat) {
                var path = Path(); path.addLines(points.map { CGPoint(x: $0.x * s, y: $0.y * s) })
                context.stroke(path, with: ink, style: StrokeStyle(lineWidth: width * s, lineCap: .round, lineJoin: .round))
            }
            func rounded(_ rect: CGRect, radius: CGFloat) -> Path {
                Path(roundedRect: CGRect(x: rect.minX * s, y: rect.minY * s, width: rect.width * s, height: rect.height * s), cornerRadius: radius * s, style: .continuous)
            }
            func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: (x - r) * s, y: (y - r) * s, width: 2 * r * s, height: 2 * r * s))
            }
            switch id {
            case "gmail":
                context.stroke(rounded(CGRect(x: 0.08, y: 0.2, width: 0.84, height: 0.62), radius: 0.12), with: ink, lineWidth: 0.09 * s)
                line([CGPoint(x: 0.14, y: 0.28), CGPoint(x: 0.5, y: 0.56), CGPoint(x: 0.86, y: 0.28)], width: 0.09)
            case "slack":
                // Rounded hash, like Slack's mark. Avoid rotated-hook arrangements.
                for bar in [CGRect(x: 0.28, y: 0.08, width: 0.15, height: 0.84), CGRect(x: 0.57, y: 0.08, width: 0.15, height: 0.84),
                            CGRect(x: 0.08, y: 0.28, width: 0.84, height: 0.15), CGRect(x: 0.08, y: 0.57, width: 0.84, height: 0.15)] {
                    context.fill(rounded(bar, radius: 0.075), with: ink)
                }
            case "linkedin":
                context.fill(rounded(CGRect(x: 0.06, y: 0.06, width: 0.88, height: 0.88), radius: 0.2), with: ink)
                context.blendMode = .destinationOut
                context.fill(circle(0.3, 0.29, 0.075), with: ink)
                line([CGPoint(x: 0.3, y: 0.45), CGPoint(x: 0.3, y: 0.76)], width: 0.13)
                line([CGPoint(x: 0.5, y: 0.76), CGPoint(x: 0.5, y: 0.45)], width: 0.12)
                var arch = Path()
                arch.move(to: CGPoint(x: 0.5 * s, y: 0.58 * s))
                arch.addQuadCurve(to: CGPoint(x: 0.72 * s, y: 0.58 * s), control: CGPoint(x: 0.6 * s, y: 0.42 * s))
                arch.addLine(to: CGPoint(x: 0.72 * s, y: 0.76 * s))
                context.stroke(arch, with: ink, style: StrokeStyle(lineWidth: 0.12 * s, lineCap: .round, lineJoin: .round))
            case "x":
                line([CGPoint(x: 0.16, y: 0.12), CGPoint(x: 0.84, y: 0.88)], width: 0.16)
                line([CGPoint(x: 0.84, y: 0.12), CGPoint(x: 0.16, y: 0.88)], width: 0.07)
            case "instagram":
                context.stroke(rounded(CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8), radius: 0.24), with: ink, lineWidth: 0.09 * s)
                context.stroke(circle(0.5, 0.5, 0.18), with: ink, lineWidth: 0.09 * s)
                context.fill(circle(0.71, 0.29, 0.055), with: ink)
            case "facebook":
                context.fill(circle(0.5, 0.5, 0.44), with: ink)
                context.blendMode = .destinationOut
                var f = Path()
                f.move(to: CGPoint(x: 0.56 * s, y: 0.94 * s))
                f.addLine(to: CGPoint(x: 0.56 * s, y: 0.42 * s))
                f.addQuadCurve(to: CGPoint(x: 0.72 * s, y: 0.26 * s), control: CGPoint(x: 0.56 * s, y: 0.26 * s))
                context.stroke(f, with: ink, style: StrokeStyle(lineWidth: 0.13 * s, lineCap: .round))
                line([CGPoint(x: 0.42, y: 0.53), CGPoint(x: 0.7, y: 0.53)], width: 0.11)
            case "reddit":
                context.fill(Path(ellipseIn: CGRect(x: 0.1 * s, y: 0.34 * s, width: 0.8 * s, height: 0.56 * s)), with: ink)
                context.fill(circle(0.76, 0.14, 0.08), with: ink)
                line([CGPoint(x: 0.5, y: 0.36), CGPoint(x: 0.56, y: 0.12), CGPoint(x: 0.72, y: 0.15)], width: 0.06)
                context.blendMode = .destinationOut
                context.fill(circle(0.36, 0.58, 0.07), with: ink)
                context.fill(circle(0.64, 0.58, 0.07), with: ink)
            case "tiktok":
                context.fill(circle(0.36, 0.72, 0.18), with: ink)
                line([CGPoint(x: 0.53, y: 0.72), CGPoint(x: 0.53, y: 0.1)], width: 0.13)
                var tail = Path()
                tail.move(to: CGPoint(x: 0.53 * s, y: 0.12 * s))
                tail.addQuadCurve(to: CGPoint(x: 0.84 * s, y: 0.36 * s), control: CGPoint(x: 0.6 * s, y: 0.34 * s))
                context.stroke(tail, with: ink, style: StrokeStyle(lineWidth: 0.11 * s, lineCap: .round))
            case "whatsapp":
                var bubble = Path(ellipseIn: CGRect(x: 0.12 * s, y: 0.08 * s, width: 0.8 * s, height: 0.8 * s))
                bubble.move(to: CGPoint(x: 0.2 * s, y: 0.7 * s))
                bubble.addLine(to: CGPoint(x: 0.08 * s, y: 0.94 * s))
                bubble.addLine(to: CGPoint(x: 0.34 * s, y: 0.84 * s))
                context.stroke(bubble, with: ink, style: StrokeStyle(lineWidth: 0.08 * s, lineJoin: .round))
                var handset = Path()
                handset.move(to: CGPoint(x: 0.38 * s, y: 0.32 * s))
                handset.addQuadCurve(to: CGPoint(x: 0.66 * s, y: 0.62 * s), control: CGPoint(x: 0.38 * s, y: 0.6 * s))
                context.stroke(handset, with: ink, style: StrokeStyle(lineWidth: 0.12 * s, lineCap: .round))
            default:
                if let symbol = context.resolveSymbol(id: 0) { context.draw(symbol, in: CGRect(x: 0, y: 0, width: s, height: s)) }
            }
        } symbols: {
            Image(systemName: "globe").resizable().scaledToFit().tag(0)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Up to three overlapping marks that summarise a mode at a glance.
struct ModeGlyphs: View {
    let selection: BlockSelection
    var body: some View {
        let ids = BlockingPreset.all.filter { selection.fullyContains($0) }.map(\.id)
        HStack(spacing: -4) {
            if ids.isEmpty {
                Image(systemName: "square.dashed").font(.system(size: 13)).frame(width: 22, height: 22)
            }
            ForEach(Array(ids.prefix(3)), id: \.self) { id in
                BrandGlyph(id: id, size: 12)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(OrtusTheme.cardSurface))
                    .overlay(Circle().strokeBorder(OrtusTheme.hairline, lineWidth: 1))
            }
        }
        .foregroundStyle(.primary)
    }
}
