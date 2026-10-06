import SwiftUI
import OrtusCore

// MARK: - Panel modals

/// Dialogs shown over the whole panel. A MenuBarExtra window can't host sheets
/// reliably, so modals are drawn inside the panel instead.
enum PanelModal {
    case browserSetup
    case slackSetup
    case modeEditor(FocusMode, onSave: (FocusMode) -> Void)
}

@MainActor
final class PanelRouter: ObservableObject {
    @Published var modal: PanelModal?
    init(modal: PanelModal? = nil) { self.modal = modal }
}

/// The one modal shape: dimmed panel, a lifted card with a title and a close button.
struct OrtusModal<Content: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(title).font(OrtusTheme.Typo.headline)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(OrtusTheme.textMuted)
                            .frame(width: 26, height: 26).background(Circle().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(OrtusPressableStyle(cornerRadius: 13)).keyboardShortcut(.cancelAction).accessibilityLabel("Close")
                }
                .padding(OrtusTheme.spacingMD)
                ScrollView {
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding([.horizontal, .bottom], OrtusTheme.spacingMD)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .background(RoundedRectangle(cornerRadius: OrtusTheme.radiusLG, style: .continuous).fill(OrtusTheme.cardSurface))
            .overlay(RoundedRectangle(cornerRadius: OrtusTheme.radiusLG, style: .continuous).strokeBorder(OrtusTheme.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 24, y: 8)
            .padding(OrtusTheme.spacingMD)
        }
    }
}

// MARK: - List rows

/// The one row anatomy used everywhere: icon column, title with an optional status
/// line, and a single trailing control.
struct OrtusListRow<Icon: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var icon: Icon
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            icon
                .font(.system(size: 15))
                .frame(width: 22, height: 22)
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(OrtusTheme.Typo.bodyMedium)
                if let subtitle {
                    Text(subtitle).font(OrtusTheme.Typo.caption).foregroundStyle(OrtusTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .frame(minHeight: 30)
        .padding(.horizontal, OrtusTheme.spacingMD)
        .padding(.vertical, 11)
    }
}

/// A card holding rows. Put `OrtusGroupDivider()` between rows.
struct OrtusGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous)
        VStack(spacing: 0) { content }
            .background(shape.fill(OrtusTheme.cardSurface))
            .overlay(shape.strokeBorder(OrtusTheme.hairline, lineWidth: 1))
            .clipShape(shape)
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

/// Hairline between rows, aligned with the row text.
struct OrtusGroupDivider: View {
    var body: some View { Rectangle().fill(OrtusTheme.hairline).frame(height: 1).padding(.leading, 50) }
}

/// A numbered setup step, used by every setup modal.
struct OrtusStepRow<Trailing: View>: View {
    let number: Int
    let title: String
    var detail: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        OrtusListRow(title: title, subtitle: detail) {
            Text("\(number)")
                .font(OrtusTheme.Typo.badge).monospacedDigit()
                .frame(width: 22, height: 22)
                .background(Circle().fill(OrtusTheme.accentSoft))
                .foregroundStyle(OrtusTheme.accentInk)
        } trailing: { trailing }
    }
}

/// Compact capsule for the trailing action of a row.
struct OrtusRowButtonStyle: ButtonStyle {
    var role: ButtonRole? = nil
    func makeBody(configuration: Configuration) -> some View { RowButton(configuration: configuration, destructive: role == .destructive) }

    private struct RowButton: View {
        let configuration: Configuration
        let destructive: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false
        var body: some View {
            let tint = destructive ? OrtusTheme.danger : Color.primary
            configuration.label
                .font(OrtusTheme.Typo.button)
                .foregroundStyle(destructive ? OrtusTheme.danger : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.16 : isHovering && isEnabled ? 0.1 : 0.05)))
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: isHovering)
                .onHover { isHovering = $0 }
        }
    }
}

/// For anything clickable that has no button chrome of its own (rows, chips, icons,
/// text actions): a soft highlight on hover and a small press-in on click.
struct OrtusPressableStyle: ButtonStyle {
    /// Extra room for the hover highlight around the label, without changing layout.
    var inset: CGFloat = 0
    var cornerRadius: CGFloat = 8
    /// Off for controls that already draw their own hover state.
    var highlight = true
    func makeBody(configuration: Configuration) -> some View {
        Pressable(configuration: configuration, inset: inset, cornerRadius: cornerRadius, highlight: highlight)
    }

    private struct Pressable: View {
        let configuration: Configuration
        let inset: CGFloat
        let cornerRadius: CGFloat
        let highlight: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false
        var body: some View {
            let fill = !highlight || !isEnabled ? 0 : configuration.isPressed ? 0.09 : isHovering ? 0.05 : 0
            configuration.label
                .padding(inset)
                .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Color.primary.opacity(fill)))
                .contentShape(Rectangle())
                .padding(-inset)
                .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: isHovering)
                .onHover { isHovering = $0 }
        }
    }
}

// MARK: - Flow layout

/// Wraps chips onto as many lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + size.width <= width {
                rows[rows.count - 1] = (last.indices + [index], last.width + spacing + size.width, max(last.height, size.height))
            } else {
                rows.append(([index], size.width, size.height))
            }
        }
        return rows
    }
}
