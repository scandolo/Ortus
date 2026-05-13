import AppKit
import SwiftUI

/// Bespoke duration slider for Ortus's focus picker. Replaces SwiftUI's stock `Slider`
/// with a sunrise visual metaphor:
///
///   • Track fills with a cream → amber → deep-amber gradient as duration grows.
///   • The thumb is a small "sun" whose hue, glow, and halo intensity ramp up with the value.
///   • A floating value chip with a downward tail follows the thumb during drag.
///     The chip body clamps inside the track bounds, but the tail offsets within the chip
///     so the tip stays aimed at the thumb (animatable).
///   • Snaps to caller-supplied tick values, with a macOS alignment haptic + a chip pulse
///     each time you cross a tick.
///   • Number rolls over with `.contentTransition(.numericText)`.
///
/// Designed to sit inside an `ortusCard()`.
struct OrtusDurationSlider: View {
    @Binding var minutes: Double
    let range: ClosedRange<Double>
    let ticks: [Double]
    let step: Double

    @State private var isDragging = false
    @State private var lastSnappedTick: Double? = nil
    @State private var chipPulse: CGFloat = 1.0

    // Layout constants
    private let trackHeight: CGFloat = 8
    private let thumbSize: CGFloat = 26
    private let chipWidth: CGFloat = 66
    private let chipHeight: CGFloat = 30
    private let chipTailHeight: CGFloat = 5
    private let chipGap: CGFloat = 8       // chip tail tip → thumb top
    private let labelGap: CGFloat = 6      // thumb bottom → range labels
    private let labelHeight: CGFloat = 14

    private var totalHeight: CGFloat {
        chipHeight + chipGap + thumbSize + labelGap + labelHeight
    }

    var body: some View {
        GeometryReader { proxy in
            sliderContent(width: proxy.size.width)
        }
        .frame(height: totalHeight)
    }

    // MARK: - Composition

    private func sliderContent(width: CGFloat) -> some View {
        let thumbX = positionFor(value: minutes, width: width)
        let thumbCY = chipHeight + chipGap + thumbSize / 2
        let p = self.progress
        let usable = width - thumbSize
        let filledWidth = max(trackHeight, thumbSize / 2 + p * usable)
        let chipCX = clampedChipX(thumbX: thumbX, width: width)
        let tailOffsetX = thumbX - chipCX

        return ZStack {
            // ── Track background ──
            Capsule()
                .fill(OrtusTheme.hairline)
                .frame(width: width, height: trackHeight)
                .position(x: width / 2, y: thumbCY)

            // ── Filled portion (sunrise gradient, left-anchored) ──
            Capsule()
                .fill(sunriseGradient)
                .frame(width: filledWidth, height: trackHeight)
                .position(x: filledWidth / 2, y: thumbCY)
                .shadow(color: OrtusTheme.accent.opacity(0.35), radius: 6, y: 1)

            // ── Tick dots ──
            ForEach(ticks, id: \.self) { tick in
                let x = positionFor(value: tick, width: width)
                let past = tick <= minutes + 0.0001
                Circle()
                    .fill(past ? Color.white.opacity(0.85) : OrtusTheme.textMuted.opacity(0.4))
                    .frame(width: 3, height: 3)
                    .scaleEffect(past ? 1.0 : 0.85)
                    .position(x: x, y: thumbCY)
                    .animation(.easeOut(duration: 0.18), value: past)
            }

            // ── Range labels ──
            HStack {
                Text(label(range.lowerBound))
                Spacer()
                Text(label(range.upperBound))
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(OrtusTheme.textMuted)
            .frame(width: width)
            .position(x: width / 2, y: thumbCY + thumbSize / 2 + labelGap + labelHeight / 2)

            // ── Sun thumb ──
            sunThumb
                .position(x: thumbX, y: thumbCY)

            // ── Floating chip (centered on chipCX; tail aimed at thumbX) ──
            chip(tailOffsetX: tailOffsetX)
                .position(x: chipCX, y: chipHeight / 2)
        }
        .frame(width: width, height: totalHeight)
        .contentShape(Rectangle())
        .gesture(dragGesture(width: width))
    }

    // MARK: - Thumb

    private var sunThumb: some View {
        let i = progress  // 0 → 1
        return ZStack {
            // Outer breathing halo
            Circle()
                .fill(OrtusTheme.accent.opacity(0.18 + 0.30 * i))
                .frame(width: thumbSize * 2.3, height: thumbSize * 2.3)
                .blur(radius: 9)
                .scaleEffect(isDragging ? 1.18 : 1.0)

            // Inner soft glow ring
            Circle()
                .stroke(OrtusTheme.accent.opacity(0.30 + 0.40 * i), lineWidth: 2)
                .frame(width: thumbSize + 6, height: thumbSize + 6)
                .blur(radius: 2)
                .opacity(isDragging ? 1.0 : 0.7)

            // Sun body — radial gradient warming with intensity
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            sunCenterColor(i),
                            sunEdgeColor(i)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: thumbSize / 2
                    )
                )
                .frame(width: thumbSize, height: thumbSize)
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                )
                .shadow(color: OrtusTheme.accent.opacity(0.45 + 0.30 * i), radius: 8, y: 2)
                .shadow(color: .black.opacity(0.20), radius: 2, y: 1)
                .scaleEffect(isDragging ? 1.10 : 1.0)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isDragging)
        .animation(.easeOut(duration: 0.25), value: progress)
    }

    // MARK: - Chip

    private func chip(tailOffsetX: CGFloat) -> some View {
        let shape = ChipShape(tailOffsetX: tailOffsetX)
        return ZStack {
            shape
                .fill(OrtusTheme.cardSurface)
                .overlay(shape.stroke(OrtusTheme.accent.opacity(0.55), lineWidth: 1))

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(Int(minutes))")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText(value: minutes))

                Text("min")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            // Offset upward by half the tail height so visual center sits in the bubble portion.
            .offset(y: -chipTailHeight / 2)
        }
        .frame(width: chipWidth, height: chipHeight)
        .shadow(color: .black.opacity(0.14), radius: 5, y: 2)
        .scaleEffect(chipPulse)
    }

    // MARK: - Geometry

    private var progress: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return (minutes - range.lowerBound) / span
    }

    private func positionFor(value: Double, width: CGFloat) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        let p = span > 0 ? (value - range.lowerBound) / span : 0
        let usable = width - thumbSize
        return thumbSize / 2 + CGFloat(p) * usable
    }

    private func valueFor(position: CGFloat, width: CGFloat) -> Double {
        let usable = width - thumbSize
        guard usable > 0 else { return range.lowerBound }
        let raw = Double((position - thumbSize / 2) / usable)
            * (range.upperBound - range.lowerBound)
            + range.lowerBound
        return min(max(raw, range.lowerBound), range.upperBound)
    }

    private func snappedValue(_ raw: Double) -> Double {
        let snapThreshold: Double = 4
        for tick in ticks where abs(tick - raw) <= snapThreshold {
            return tick
        }
        return (raw / step).rounded() * step
    }

    private func clampedChipX(thumbX: CGFloat, width: CGFloat) -> CGFloat {
        let half = chipWidth / 2
        return min(max(thumbX, half), width - half)
    }

    private func label(_ minutes: Double) -> String {
        let m = Int(minutes)
        if m >= 60 && m % 60 == 0 { return "\(m / 60)h" }
        return "\(m)m"
    }

    private var sunriseGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.88, blue: 0.70),   // dawn cream
                OrtusTheme.accent,                            // mid-morning amber
                OrtusTheme.accentHover                        // deep midday amber
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func sunCenterColor(_ intensity: Double) -> Color {
        // Pale cream → vivid yellow-amber
        Color(red: 1.0,
              green: 0.96 - 0.10 * intensity,
              blue: 0.86 - 0.50 * intensity)
    }

    private func sunEdgeColor(_ intensity: Double) -> Color {
        Color(red: 0.96 - 0.04 * intensity,
              green: 0.76 - 0.30 * intensity,
              blue: 0.50 - 0.30 * intensity)
    }

    // MARK: - Interaction

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if !isDragging { isDragging = true }
                let raw = valueFor(position: gesture.location.x, width: width)
                let snapped = snappedValue(raw)
                playHapticIfTickCrossed(snapped)
                withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.86)) {
                    minutes = snapped
                }
            }
            .onEnded { _ in
                isDragging = false
                lastSnappedTick = nil
            }
    }

    private func playHapticIfTickCrossed(_ value: Double) {
        guard ticks.contains(value) else { return }
        guard lastSnappedTick != value else { return }
        lastSnappedTick = value
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) {
            chipPulse = 1.14
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                chipPulse = 1.0
            }
        }
    }
}

// MARK: - Chip Shape (rounded rect + downward tail)
//
// `tailOffsetX` shifts the tail tip horizontally from the bubble's center. The tail is
// clamped to remain within the rounded-corner area of the bubble bottom so it doesn't
// detach from the body. Animatable so the tail glides while the chip body stays clamped.

private struct ChipShape: Shape {
    var tailOffsetX: CGFloat
    var tailHeight: CGFloat = 5
    var tailHalfWidth: CGFloat = 5
    var cornerRadius: CGFloat = 9

    var animatableData: CGFloat {
        get { tailOffsetX }
        set { tailOffsetX = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let bubbleBottom = rect.maxY - tailHeight
        let r = cornerRadius

        let tailCenter = rect.midX + tailOffsetX
        let minTail = rect.minX + r + tailHalfWidth
        let maxTail = rect.maxX - r - tailHalfWidth
        let clampedTail = min(max(tailCenter, minTail), maxTail)

        var path = Path()
        // Top edge (left → right)
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + r),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        // Right edge
        path.addLine(to: CGPoint(x: rect.maxX, y: bubbleBottom - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: bubbleBottom),
            control: CGPoint(x: rect.maxX, y: bubbleBottom)
        )
        // Bottom edge → tail right shoulder
        path.addLine(to: CGPoint(x: clampedTail + tailHalfWidth, y: bubbleBottom))
        // Tail down to point
        path.addLine(to: CGPoint(x: clampedTail, y: rect.maxY))
        // Tail back up to left shoulder
        path.addLine(to: CGPoint(x: clampedTail - tailHalfWidth, y: bubbleBottom))
        // Bottom edge → left
        path.addLine(to: CGPoint(x: rect.minX + r, y: bubbleBottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: bubbleBottom - r),
            control: CGPoint(x: rect.minX, y: bubbleBottom)
        )
        // Left edge
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + r, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
