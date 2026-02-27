import SwiftUI

// MARK: - Design System

enum OrtusTheme {
    // MARK: Colors

    static let primary = Color.indigo
    static let primaryLight = Color.indigo.opacity(0.12)
    static let warning = Color.orange
    static let warningLight = Color.orange.opacity(0.12)
    static let success = Color.green
    static let destructive = Color.red
    static let subtleBackground = Color.primary.opacity(0.04)

    // MARK: Spacing

    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 16
    static let spacingLG: CGFloat = 24
    static let spacingXL: CGFloat = 32

    // MARK: Corner Radii

    static let radiusSM: CGFloat = 8
    static let radiusMD: CGFloat = 12
    static let radiusLG: CGFloat = 16
}

// MARK: - Card Modifier

struct OrtusCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(OrtusTheme.spacingMD)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
    }
}

extension View {
    func ortusCard() -> some View {
        modifier(OrtusCardModifier())
    }
}

// MARK: - Primary Button Style

struct OrtusPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, OrtusTheme.spacingMD)
            .padding(.vertical, OrtusTheme.spacingSM)
            .background(
                RoundedRectangle(cornerRadius: OrtusTheme.radiusSM, style: .continuous)
                    .fill(OrtusTheme.primary)
                    .opacity(configuration.isPressed ? 0.8 : 1)
            )
    }
}

// MARK: - Empty State

struct OrtusEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: OrtusTheme.spacingMD) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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
            .font(.caption.weight(.semibold))
            .tracking(0.5)
            .foregroundStyle(.secondary)
    }
}
