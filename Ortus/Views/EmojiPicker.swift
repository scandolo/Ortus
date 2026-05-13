import SwiftUI

/// Compact button that shows the currently-selected emoji as a real glyph and
/// opens a popover picker. Persists Slack `:shortcode:` strings via the binding.
struct EmojiPickerButton: View {
    @Binding var code: String

    @State private var showPopover = false

    private var renderedGlyph: String {
        EmojiCatalog.glyph(for: code) ?? "💬"
    }

    private var hasCustomCode: Bool {
        !code.isEmpty && EmojiCatalog.glyph(for: code) == nil
    }

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(renderedGlyph)
                    .font(.system(size: 18))
                if hasCustomCode {
                    Text(EmojiCatalog.normalize(code))
                        .font(OrtusTheme.Typo.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: OrtusTheme.radiusSM, style: .continuous)
                    .fill(OrtusTheme.inputSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OrtusTheme.radiusSM, style: .continuous)
                    .strokeBorder(OrtusTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            EmojiPickerPopover(code: $code, isPresented: $showPopover)
        }
    }
}

/// Searchable, categorized emoji grid with a "custom code" fallback for workspace emoji.
struct EmojiPickerPopover: View {
    @Binding var code: String
    @Binding var isPresented: Bool

    @State private var query: String = ""
    @State private var showCustom = false
    @State private var customCode: String = ""

    private let columns = Array(repeating: GridItem(.fixed(34), spacing: 2), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: OrtusTheme.spacingSM) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                TextField("Search emoji", text: $query)
                    .textFieldStyle(.plain)
                    .font(OrtusTheme.Typo.body)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: OrtusTheme.radiusSM, style: .continuous)
                    .fill(OrtusTheme.inputSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OrtusTheme.radiusSM, style: .continuous)
                    .strokeBorder(OrtusTheme.hairline, lineWidth: 1)
            )

            ScrollView {
                VStack(alignment: .leading, spacing: OrtusTheme.spacingSM) {
                    if query.isEmpty {
                        ForEach(EmojiCatalog.sections, id: \.title) { section in
                            sectionView(title: section.title, entries: section.entries)
                        }
                    } else {
                        let results = EmojiCatalog.search(query)
                        if results.isEmpty {
                            Text("No matches. Try a custom code below for workspace emoji.")
                                .font(OrtusTheme.Typo.caption)
                                .foregroundStyle(OrtusTheme.textMuted)
                                .padding(.vertical, 4)
                        } else {
                            sectionView(title: "Results", entries: results)
                        }
                    }
                }
            }
            .frame(width: 304, height: 240)

            customCodeRow
        }
        .padding(OrtusTheme.spacingSM)
        .frame(width: 320)
        .background(OrtusTheme.cardSurface)
    }

    private func sectionView(title: String, entries: [EmojiCatalog.Entry]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(OrtusTheme.Typo.section)
                .tracking(1.2)
                .foregroundStyle(OrtusTheme.textMuted)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(entries, id: \.code) { entry in
                    emojiCell(entry)
                }
            }
        }
    }

    private func emojiCell(_ entry: EmojiCatalog.Entry) -> some View {
        let isSelected = EmojiCatalog.normalize(code) == entry.code
        return Button {
            code = entry.code
            isPresented = false
        } label: {
            Text(entry.glyph)
                .font(.system(size: 20))
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: OrtusTheme.radiusSM, style: .continuous)
                        .fill(isSelected ? OrtusTheme.accentSoft : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OrtusTheme.radiusSM, style: .continuous)
                        .strokeBorder(isSelected ? OrtusTheme.accent : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(entry.code)
    }

    @ViewBuilder
    private var customCodeRow: some View {
        if showCustom {
            VStack(alignment: .leading, spacing: 6) {
                Text("Custom Slack code (for workspace emoji)")
                    .font(OrtusTheme.Typo.meta)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    TextField(":my_company_logo:", text: $customCode)
                        .textFieldStyle(OrtusTextFieldStyle())
                    Button("Use") {
                        let normalized = EmojiCatalog.normalize(customCode)
                        guard normalized != ":" else { return }
                        code = normalized
                        isPresented = false
                    }
                    .buttonStyle(OrtusGhostButtonStyle())
                    .disabled(customCode.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if EmojiCatalog.glyph(for: code) == nil {
                    customCode = code
                }
            }
        } else {
            HStack {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { showCustom = true }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 10, weight: .bold))
                        Text("Use a custom code")
                    }
                    .font(OrtusTheme.Typo.caption)
                    .foregroundStyle(OrtusTheme.accent)
                }
                .buttonStyle(.plain)
                Spacer()
                Button("Clear") {
                    code = ""
                    isPresented = false
                }
                .buttonStyle(.plain)
                .font(OrtusTheme.Typo.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}
