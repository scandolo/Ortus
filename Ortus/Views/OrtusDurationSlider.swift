import AppKit
import SwiftUI

/// The session length, as a straight line: an ink fill over a sand track and a squircle
/// thumb. The number itself sits above the slider in the Focus card, in Archivo Black.
/// Snaps to the caller's ticks, with an alignment haptic each time it lands on one.
struct OrtusDurationSlider: View {
    @Binding var minutes: Double
    let range: ClosedRange<Double>
    let ticks: [Double]
    let step: Double

    @State private var isDragging = false
    @State private var lastSnappedTick: Double? = nil

    private let thumbWidth: CGFloat = 24
    private let thumbHeight: CGFloat = 22

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let x = positionFor(value: minutes, width: width)
            ZStack(alignment: .leading) {
                Rectangle().fill(OrtusTheme.line).frame(height: 4)
                Rectangle().fill(OrtusTheme.strong).frame(width: x, height: 6)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(OrtusTheme.strong)
                    .frame(width: thumbWidth, height: thumbHeight)
                    .scaleEffect(isDragging ? 1.08 : 1)
                    .offset(x: x - thumbWidth / 2)
            }
            .frame(width: width, height: thumbHeight)
            // A taller grab area than the line itself, like the old slider, without
            // changing the layout.
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .gesture(dragGesture(width: width))
            .padding(.vertical, -14)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isDragging)
        }
        .frame(height: thumbHeight)
        .accessibilityElement()
        .accessibilityLabel("Session length")
        .accessibilityValue("\(Int(minutes)) minutes")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: minutes = min(range.upperBound, minutes + step)
            case .decrement: minutes = max(range.lowerBound, minutes - step)
            @unknown default: break
            }
        }
    }

    // MARK: - Geometry

    private func positionFor(value: Double, width: CGFloat) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        let p = span > 0 ? (value - range.lowerBound) / span : 0
        let usable = width - thumbWidth
        return thumbWidth / 2 + CGFloat(p) * usable
    }

    private func valueFor(position: CGFloat, width: CGFloat) -> Double {
        let usable = width - thumbWidth
        guard usable > 0 else { return range.lowerBound }
        let raw = Double((position - thumbWidth / 2) / usable) * (range.upperBound - range.lowerBound) + range.lowerBound
        return min(max(raw, range.lowerBound), range.upperBound)
    }

    private func snappedValue(_ raw: Double) -> Double {
        let snapThreshold: Double = 4
        for tick in ticks where abs(tick - raw) <= snapThreshold {
            return tick
        }
        return (raw / step).rounded() * step
    }

    // MARK: - Interaction

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if !isDragging { isDragging = true }
                let snapped = snappedValue(valueFor(position: gesture.location.x, width: width))
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
        guard ticks.contains(value), lastSnappedTick != value else { return }
        lastSnappedTick = value
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
