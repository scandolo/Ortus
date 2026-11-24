import SwiftUI

// MARK: - Icons

/// The First Light icon set: solid shapes with real cut-outs on a 24 pt grid, drawn in
/// the current foreground style. The eight brand icons are copied from the brand kit
/// (the brand kit's icon set); the rest follow the same rules.
struct OrtusIcon: View {
    enum Name: String, CaseIterable {
        // Brand kit
        case focus, schedule, chat, settings, locked, blocked, addTime, agent
        // Same family
        case power, hide, bars, spark, update, globe, hash, mail, warn, close, plus, send
        case copy, edit, chevronRight, chevronDown, check, undo, terminal, link, shield, folder, app, key, stop
    }

    let name: Name
    var size: CGFloat = 16

    init(_ name: Name, size: CGFloat = 16) {
        self.name = name
        self.size = size
    }

    var body: some View {
        let scale = size / 24
        ZStack {
            ForEach(Array(Self.parts(name).enumerated()), id: \.offset) { _, part in
                switch part.style {
                case .fill(let evenOdd):
                    ScaledPath(path: part.path, scale: scale).fill(style: FillStyle(eoFill: evenOdd))
                case .stroke(let width):
                    ScaledPath(path: part.path, scale: scale).stroke(style: StrokeStyle(lineWidth: width * scale))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    struct Part {
        enum Style { case fill(evenOdd: Bool), stroke(CGFloat) }
        let path: Path
        let style: Style
    }

    private static func fill(_ d: String, evenOdd: Bool = true) -> Part { Part(path: SVGPath.parse(d), style: .fill(evenOdd: evenOdd)) }
    private static func stroke(_ d: String, _ width: CGFloat) -> Part { Part(path: SVGPath.parse(d), style: .stroke(width)) }
    private static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, radius: CGFloat = 0) -> Part {
        let r = CGRect(x: x, y: y, width: w, height: h)
        return Part(path: radius > 0 ? Path(roundedRect: r, cornerRadius: radius) : Path(r), style: .fill(evenOdd: false))
    }

    // Parsed once per name.
    @MainActor private static var cache: [Name: [Part]] = [:]

    @MainActor static func parts(_ name: Name) -> [Part] {
        if let parts = cache[name] { return parts }
        let parts = build(name)
        cache[name] = parts
        return parts
    }

    private static func build(_ name: Name) -> [Part] {
        switch name {
        case .focus:
            return [fill("M3 15a9 9 0 0 1 18 0Z", evenOdd: false), rect(1.5, 16.5, 21, 2.6), rect(4, 20.6, 16, 1.8)]
        case .schedule:
            return [fill("M3 5h18v16H3ZM6 11h12v7H6Z"), rect(7, 2, 3, 5), rect(14, 2, 3, 5)]
        case .chat:
            return [fill("M7 3.5h10a5 5 0 0 1 5 5v4a5 5 0 0 1-5 5h-6l-5.5 4v-4.2A5 5 0 0 1 2 12.5v-4a5 5 0 0 1 5-5ZM6.3 9.3h2.6v2.6H6.3ZM10.7 9.3h2.6v2.6h-2.6ZM15.1 9.3h2.6v2.6h-2.6Z")]
        case .settings:
            return [rect(2, 5.6, 20, 2.8), rect(2, 15.6, 20, 2.8), rect(13, 3, 5, 8, radius: 1.2), rect(5.5, 13, 5, 8, radius: 1.2)]
        case .locked:
            return [stroke("M8 11V8a4 4 0 0 1 8 0v3", 3), fill("M4 10.5h16V22H4ZM10.8 14h2.4v4.5h-2.4Z")]
        case .blocked:
            return [fill("M12 2a10 10 0 1 1 0 20a10 10 0 1 1 0-20ZM16.5 5.8L18.2 7.5L7.5 18.2L5.8 16.5Z")]
        case .addTime:
            return [fill("M12 2a10 10 0 1 1 0 20a10 10 0 1 1 0-20ZM10.8 6.5h2.4v4.3h4.3v2.4h-4.3v4.3h-2.4v-4.3H6.5v-2.4h4.3Z")]
        case .agent:
            return [fill("M4 7h16v13H4ZM8 11h3v3H8ZM13 11h3v3h-3Z"), rect(10.8, 3, 2.4, 4)]
        case .power:
            return [stroke("M7 5.5a8 8 0 1 0 10 0", 2.8), rect(10.6, 2, 2.8, 10)]
        case .hide:
            return [fill("M2 8h14v13H2ZM4.6 10.6h8.8v7.8H4.6Z"), fill("M7 3h15v13h-4v-2.6h1.4V5.6H9.6V6H7Z", evenOdd: false)]
        case .bars:
            return [rect(3, 12, 4.5, 9), rect(9.75, 7, 4.5, 14), rect(16.5, 3, 4.5, 18)]
        case .spark:
            return [fill("M12 2l2.6 7.4L22 12l-7.4 2.6L12 22l-2.6-7.4L2 12l7.4-2.6Z", evenOdd: false)]
        case .update:
            return [fill("M12 2a10 10 0 1 1 0 20a10 10 0 1 1 0-20ZM10.8 6h2.4v6.2l2.6-2.6l1.7 1.7L12 16.8l-5.5-5.5l1.7-1.7l2.6 2.6Z")]
        case .globe:
            return [fill("M12 2a10 10 0 1 1 0 20a10 10 0 1 1 0-20ZM4.7 10.8h3.9c.1-2.3.6-4.4 1.4-5.9a7.6 7.6 0 0 0-5.3 5.9ZM11 10.8h2c-.1-2.6-.6-4.5-1-5.4c-.4.9-.9 2.8-1 5.4ZM15.4 10.8h3.9a7.6 7.6 0 0 0-5.3-5.9c.8 1.5 1.3 3.6 1.4 5.9ZM4.7 13.2a7.6 7.6 0 0 0 5.3 5.9c-.8-1.5-1.3-3.6-1.4-5.9ZM11 13.2c.1 2.6.6 4.5 1 5.4c.4-.9.9-2.8 1-5.4ZM15.4 13.2c-.1 2.3-.6 4.4-1.4 5.9a7.6 7.6 0 0 0 5.3-5.9Z")]
        case .hash:
            return [rect(7, 2, 2.8, 20), rect(14.2, 2, 2.8, 20), rect(2, 7, 20, 2.8), rect(2, 14.2, 20, 2.8)]
        case .mail:
            return [fill("M2 4.5h20v15H2ZM4.8 7.6v9.2h14.4V7.6L12 12.6Z")]
        case .warn:
            return [fill("M12 2l11 19H1ZM10.8 9h2.4v5.5h-2.4ZM10.8 16h2.4v2.4h-2.4Z")]
        case .close:
            return [fill("M5.6 3.6L12 10l6.4-6.4l2 2L14 12l6.4 6.4l-2 2L12 14l-6.4 6.4l-2-2L10 12L3.6 5.6Z", evenOdd: false)]
        case .plus:
            return [fill("M10.6 3h2.8v7.6H21v2.8h-7.6V21h-2.8v-7.6H3v-2.8h7.6Z", evenOdd: false)]
        case .send:
            return [fill("M12 3l8 8l-2 2l-4.6-4.6V21h-2.8V8.4L6 13l-2-2Z", evenOdd: false)]
        case .copy:
            return [fill("M8 2h13v15h-5v-2.6h2.4V4.6h-7.8V6H8Z"), fill("M3 7h13v15H3ZM5.6 9.6v9.8h7.8V9.6Z")]
        case .edit:
            return [fill("M15.5 3.5l5 5L9 20H4v-5Z", evenOdd: false)]
        case .chevronRight:
            return [fill("M8.6 4.4L16.2 12l-7.6 7.6l-2-2L12.2 12L6.6 6.4Z", evenOdd: false)]
        case .chevronDown:
            return [fill("M4.4 8.6L12 16.2l7.6-7.6l-2-2L12 12.2L6.4 6.6Z", evenOdd: false)]
        case .check:
            return [fill("M9.5 15.2L19.3 5.4l2.2 2.2L9.5 19.6L2.6 12.7l2.2-2.2Z", evenOdd: false)]
        case .undo:
            return [fill("M9 3.5l2 2L8.1 8.4H14a7 7 0 0 1 0 14h-4v-2.8h4a4.2 4.2 0 0 0 0-8.4H8.1l2.9 2.9l-2 2L2.6 9.8Z", evenOdd: false)]
        case .terminal:
            return [fill("M2 4h20v16H2ZM4.6 6.6v10.8h14.8V6.6Z"), fill("M6.5 9.2l1.6-1.6l4 4l-4 4l-1.6-1.6l2.4-2.4ZM12.5 14h5v2.2h-5Z", evenOdd: false)]
        case .link:
            return [fill("M3 9h9v6H3ZM5.4 11.2v1.6h4.4v-1.6Z"), fill("M12 9h9v6h-9ZM14.2 11.2v1.6h4.4v-1.6Z")]
        case .shield:
            return [fill("M12 2l9 3.5v6.5c0 5-3.8 8.8-9 10c-5.2-1.2-9-5-9-10V5.5ZM10.6 13.1l-2.4-2.4l-1.8 1.8l4.2 4.2l7.2-7.2l-1.8-1.8Z")]
        case .folder:
            return [fill("M2 4h8l2 2.5h10V20H2Z", evenOdd: false)]
        case .app:
            return [fill("M3 3h18v18H3ZM5.6 8.2v10.2h12.8V8.2Z")]
        case .key:
            return [fill("M8 6a6 6 0 1 1 0 12a6 6 0 1 1 0-12ZM8 10.2a1.8 1.8 0 1 0 0 3.6a1.8 1.8 0 1 0 0-3.6Z"), rect(13, 10.6, 9, 2.8), rect(18.2, 13, 2.8, 4)]
        case .stop:
            return [rect(5, 5, 14, 14, radius: 2)]
        }
    }
}

private struct ScaledPath: Shape {
    let path: Path
    let scale: CGFloat
    func path(in rect: CGRect) -> Path { path.applying(CGAffineTransform(scaleX: scale, y: scale)) }
}

// MARK: - The mark

/// The Ortus sun, copied from the brand kit (logo/ortus-mark.svg, 52 × 38). Never redrawn,
/// animated into a story or recoloured per screen.
struct OrtusMark: View {
    var width: CGFloat = 46
    var color: Color = OrtusTheme.accent

    static let viewBox = CGSize(width: 52, height: 38)

    @MainActor static let path: Path = {
        var path = SVGPath.parse("M3.5 26.5a22.5 22.5 0 0 1 45 0Z")
        path.addPath(SVGPath.parse("M1.6 28.5H51L50.4 32.1H1Z"))
        path.addPath(SVGPath.parse("M9.3 35H43L42.7 36.6H9Z"))
        return path
    }()

    var body: some View {
        let scale = width / Self.viewBox.width
        ScaledPath(path: Self.path, scale: scale)
            .fill(color)
            .frame(width: width, height: Self.viewBox.height * scale)
            .accessibilityLabel("Ortus")
    }
}

/// The menu bar tile (brand kit menubar-off.svg and menubar-locked.svg), 16 pt and one
/// colour. Off: an outlined tile with the mark. Locked: a filled tile with the mark cut out.
struct OrtusMenuBarTile: View {
    let locked: Bool

    @MainActor private static let mark: Path = {
        var path = SVGPath.parse("M3.5 26.3a22.5 22.5 0 0 1 45 0Z")
        path.addPath(SVGPath.parse("M1.6 28.2H51L50.25 32.7H1Z"))
        path.addPath(SVGPath.parse("M9.4 35H43L42.6 37.6H9Z"))
        return path.applying(CGAffineTransform(scaleX: 0.208, y: 0.208).concatenating(CGAffineTransform(translationX: 2.6, y: 4.4)))
    }()

    var body: some View {
        ZStack {
            if locked {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.black)
                ScaledPath(path: Self.mark, scale: 1).fill(Color.black).blendMode(.destinationOut)
            } else {
                RoundedRectangle(cornerRadius: 3.6, style: .continuous).strokeBorder(Color.black, lineWidth: 1.4)
                ScaledPath(path: Self.mark, scale: 1).fill(Color.black)
            }
        }
        .frame(width: 16, height: 16)
        .compositingGroup()
    }
}

// MARK: - SVG paths

/// Just enough of SVG path data for the brand kit: M L H V C Q A Z, absolute and relative.
enum SVGPath {
    static func parse(_ data: String) -> Path {
        var path = Path()
        let tokens = tokenize(data)
        var index = 0
        var command: Character = "M"
        var current = CGPoint.zero
        var start = CGPoint.zero

        func number() -> CGFloat {
            guard index < tokens.count, case .number(let value) = tokens[index] else { return 0 }
            index += 1
            return value
        }
        func hasNumber() -> Bool {
            if index < tokens.count, case .number = tokens[index] { return true }
            return false
        }

        while index < tokens.count {
            if case .command(let c) = tokens[index] {
                command = c
                index += 1
            }
            let relative = command.isLowercase
            let base = relative ? current : .zero
            switch command.uppercased().first! {
            case "M":
                let p = CGPoint(x: base.x + number(), y: base.y + number())
                path.move(to: p)
                current = p; start = p
                command = relative ? "l" : "L"
            case "L":
                let p = CGPoint(x: base.x + number(), y: base.y + number())
                path.addLine(to: p); current = p
            case "H":
                let p = CGPoint(x: (relative ? current.x : 0) + number(), y: current.y)
                path.addLine(to: p); current = p
            case "V":
                let p = CGPoint(x: current.x, y: (relative ? current.y : 0) + number())
                path.addLine(to: p); current = p
            case "C":
                let c1 = CGPoint(x: base.x + number(), y: base.y + number())
                let c2 = CGPoint(x: base.x + number(), y: base.y + number())
                let p = CGPoint(x: base.x + number(), y: base.y + number())
                path.addCurve(to: p, control1: c1, control2: c2); current = p
            case "Q":
                let c = CGPoint(x: base.x + number(), y: base.y + number())
                let p = CGPoint(x: base.x + number(), y: base.y + number())
                path.addQuadCurve(to: p, control: c); current = p
            case "A":
                let rx = number(), ry = number()
                _ = number() // x-axis rotation: always 0 in the kit
                let large = number() != 0, sweep = number() != 0
                let p = CGPoint(x: base.x + number(), y: base.y + number())
                addArc(&path, from: current, to: p, rx: rx, ry: ry, large: large, sweep: sweep)
                current = p
            case "Z":
                path.closeSubpath()
                current = start
                // A number right after Z starts an implicit line from the subpath start.
                if hasNumber() { command = "L" }
            default:
                index += 1
            }
        }
        return path
    }

    private enum Token { case command(Character), number(CGFloat) }

    private static func tokenize(_ data: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(data)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isLetter, c != "e", c != "E" {
                tokens.append(.command(c)); i += 1
            } else if c.isNumber || c == "-" || c == "+" || c == "." {
                var j = i + 1
                var seenDot = c == "."
                var seenExp = false
                while j < chars.count {
                    let d = chars[j]
                    if d.isNumber { j += 1 }
                    else if d == ".", !seenDot, !seenExp { seenDot = true; j += 1 }
                    else if (d == "e" || d == "E"), !seenExp { seenExp = true; j += 1; if j < chars.count, chars[j] == "-" || chars[j] == "+" { j += 1 } }
                    else { break }
                }
                tokens.append(.number(CGFloat(Double(String(chars[i..<j])) ?? 0)))
                i = j
            } else {
                i += 1
            }
        }
        return tokens
    }

    /// SVG's endpoint arc as cubic Béziers (SVG 1.1 appendix F.6.5, no rotation).
    private static func addArc(_ path: inout Path, from p1: CGPoint, to p2: CGPoint, rx rx0: CGFloat, ry ry0: CGFloat, large: Bool, sweep: Bool) {
        guard rx0 > 0, ry0 > 0, p1 != p2 else { path.addLine(to: p2); return }
        var rx = abs(rx0), ry = abs(ry0)
        let x1p = (p1.x - p2.x) / 2, y1p = (p1.y - p2.y) / 2
        let lambda = x1p * x1p / (rx * rx) + y1p * y1p / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
        let numerator = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let coefficient = (large != sweep ? 1 : -1) * sqrt(max(0, numerator / denominator))
        let cxp = coefficient * rx * y1p / ry
        let cyp = -coefficient * ry * x1p / rx
        let center = CGPoint(x: cxp + (p1.x + p2.x) / 2, y: cyp + (p1.y + p2.y) / 2)

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        var a = theta1
        for _ in 0..<segments {
            let b = a + step
            let k = 4 / 3 * tan((b - a) / 4)
            let start = CGPoint(x: center.x + rx * cos(a), y: center.y + ry * sin(a))
            let end = CGPoint(x: center.x + rx * cos(b), y: center.y + ry * sin(b))
            let c1 = CGPoint(x: start.x - k * rx * sin(a), y: start.y + k * ry * cos(a))
            let c2 = CGPoint(x: end.x + k * rx * sin(b), y: end.y - k * ry * cos(b))
            path.addCurve(to: end, control1: c1, control2: c2)
            a = b
        }
    }
}
