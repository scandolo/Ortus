import SwiftUI
import OrtusCore

// MARK: - Panel modals

/// Dialogs shown over the whole panel. A MenuBarExtra window can't host sheets
/// reliably, so modals are drawn inside the panel instead.
enum PanelModal {
    case browserSetup
    case slackSetup
    case chatSetup
    case chatIntro
    case focusIntro(selection: BlockSelection, minutes: Double, onConfirm: () -> Void)
    case modeEditor(FocusMode, onSave: (FocusMode) -> Void)
    case endFocusEarly
}

@MainActor
final class PanelRouter: ObservableObject {
    @Published var modal: PanelModal?
    /// A tab to switch to from outside the panel, like a notification click.
    @Published var requestedTab: Int?
    init(modal: PanelModal? = nil) { self.modal = modal }
}

/// The one modal shape: the panel dims, a sheet with 18 pt corners sits over it. A big
/// title makes a statement ("No end button."); a small one names a setup form.
struct OrtusModal<Content: View>: View {
    let title: String
    var largeTitle = false
    let onClose: () -> Void
    @ViewBuilder var content: Content
    @State private var contentHeight: CGFloat?

    var body: some View {
        ZStack {
            OrtusTheme.scrim.ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Text(title)
                        .font(largeTitle ? OrtusTheme.Typo.sheetTitle : OrtusTheme.Typo.sheetTitleSmall)
                        .tracking(largeTitle ? -0.7 : 0)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(action: onClose) {
                        OrtusIcon(.close, size: 12).foregroundStyle(OrtusTheme.textMuted)
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(OrtusTheme.fill))
                    }
                    .buttonStyle(OrtusPressableStyle(cornerRadius: 9, highlight: false)).keyboardShortcut(.cancelAction).accessibilityLabel("Close")
                }
                .padding([.horizontal, .top], 20)
                .padding(.bottom, 16)
                ScrollView {
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding([.horizontal, .bottom], 20)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
                .scrollIndicators(.never)
                .frame(maxHeight: contentHeight)
            }
            .foregroundStyle(OrtusTheme.text)
            .environment(\.ortusOnCard, true)
            .background(RoundedRectangle(cornerRadius: OrtusTheme.radiusLG, style: .continuous).fill(OrtusTheme.cardSurface))
            .padding(OrtusTheme.spacingMD)
        }
    }
}

/// A short confirmation: a statement for a title, one line, and two buttons that name
/// the outcome. The safe choice is the primary.
struct OrtusAlert: View {
    let title: String
    let message: String
    let cancel: String
    let confirm: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        OrtusModal(title: title, largeTitle: true, onClose: onCancel) {
            VStack(alignment: .leading, spacing: OrtusTheme.spacingMD) {
                Text(message).font(OrtusTheme.Typo.body).foregroundStyle(OrtusTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: OrtusTheme.spacingSM) {
                    Button(action: onCancel) { Text(cancel).frame(maxWidth: .infinity) }
                        .buttonStyle(OrtusPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                    Button(action: onConfirm) { Text(confirm).frame(maxWidth: .infinity) }
                        .buttonStyle(OrtusSecondaryButtonStyle())
                }
            }
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
        HStack(spacing: 14) {
            icon
                .frame(width: 22, height: 22)
                .foregroundStyle(OrtusTheme.text)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(OrtusTheme.Typo.headline)
                    .fixedSize(horizontal: false, vertical: true)
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
        .padding(.vertical, 10)
    }
}

/// A card holding rows. Put `OrtusGroupDivider()` between rows.
struct OrtusGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: OrtusTheme.radiusLG, style: .continuous)
        VStack(spacing: 0) { content }
            .environment(\.ortusOnCard, true)
            .padding(.vertical, 4)
            .background(shape.fill(OrtusTheme.cardSurface))
            .clipShape(shape)
    }
}

/// A straight, full-width line between rows.
struct OrtusGroupDivider: View {
    var body: some View { Rectangle().fill(OrtusTheme.line).frame(height: 1) }
}

/// The number of a setup step: a small squircle in the primary colour.
struct OrtusStepNumber: View {
    let number: Int
    var body: some View {
        Text("\(number)")
            .font(OrtusTheme.Typo.badge).monospacedDigit()
            .foregroundStyle(OrtusTheme.onStrong)
            .frame(width: 24, height: 24)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(OrtusTheme.strong))
    }
}

/// A numbered setup step, used by every setup modal.
struct OrtusStepRow<Trailing: View>: View {
    let number: Int
    let title: String
    var detail: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        OrtusListRow(title: title, subtitle: detail) {
            OrtusStepNumber(number: number)
        } trailing: { trailing }
    }
}

/// A problem written where it bites: the triangle, what it breaks, and the fix on click.
/// Inside a card it sits on the inset colour (bone in white, ink in ash).
struct OrtusProblemNote: View {
    let message: String
    var actionLabel: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                OrtusProblemIcon()
                Text(message).font(OrtusTheme.Typo.caption).foregroundStyle(OrtusTheme.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let actionLabel {
                    Text(actionLabel).font(OrtusTheme.Typo.buttonSmall).underline().foregroundStyle(OrtusTheme.text)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous).fill(OrtusTheme.inset))
            .contentShape(Rectangle())
        }
        .buttonStyle(OrtusPressableStyle(cornerRadius: OrtusTheme.radiusMD, highlight: false))
        .accessibilityLabel(message)
        .accessibilityHint(actionLabel ?? "Opens the fix")
    }
}

/// A problem during a session: a card with the triangle, a title, the consequence and
/// one fix.
struct OrtusProblemCard: View {
    let title: String
    let detail: String
    let action: String
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            OrtusProblemIcon()
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(OrtusFont.text(14, .bold))
                Text(detail).font(OrtusTheme.Typo.meta).foregroundStyle(OrtusTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(action, action: onAction).buttonStyle(OrtusRowButtonStyle())
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .environment(\.ortusOnCard, true)
        .background(RoundedRectangle(cornerRadius: OrtusTheme.radiusLG, style: .continuous).fill(OrtusTheme.cardSurface))
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
                .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(OrtusTheme.text.opacity(fill)))
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
