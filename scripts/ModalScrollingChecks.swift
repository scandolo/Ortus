import AppKit
import SwiftUI

@MainActor
private final class ModalTargets: ObservableObject {
    @Published var count = 1
}

private struct ModalFixture: View {
    @ObservedObject var targets: ModalTargets

    var body: some View {
        OrtusModal(title: "Edit mode", onClose: {}) {
            VStack(alignment: .leading, spacing: OrtusTheme.spacingMD) {
                TextField("Mode name", text: .constant("Deep work")).textFieldStyle(OrtusTextFieldStyle())
                OrtusGroup {
                    ForEach(0..<targets.count, id: \.self) { index in
                        OrtusListRow(title: "Blocked target \(index + 1)") {
                            Image(systemName: "globe")
                        } trailing: {
                            Button {} label: { Image(systemName: "xmark") }
                        }
                        OrtusGroupDivider()
                    }
                    OrtusListRow(title: "Add a website") {
                        Image(systemName: "plus.circle")
                    } trailing: { EmptyView() }
                }
                Button("Save mode") {}.buttonStyle(OrtusPrimaryButtonStyle())
            }
        }
    }
}

@main
struct ModalScrollingChecks {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        for size in [CGSize(width: 420, height: 560), CGSize(width: 280, height: 320)] {
            let targets = ModalTargets()
            let hosting = NSHostingView(rootView: ModalFixture(targets: targets).frame(width: size.width, height: size.height))
            hosting.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            defer { window.contentView = nil }

            for count in [1, 6, 20, 1] {
                targets.count = count
                try await Task.sleep(for: .milliseconds(200))
                hosting.layoutSubtreeIfNeeded()
                guard let scroll = descendants(hosting).compactMap({ $0 as? NSScrollView }).first,
                      let document = scroll.documentView else { fatalError("Modal must contain a native scroll view") }
                let frame = scroll.convert(scroll.bounds, to: hosting)
                precondition(hosting.bounds.contains(frame), "Modal scroll area must stay inside the panel after adding/removing targets")
                let overflow = document.bounds.height - scroll.documentVisibleRect.height
                if count >= 6 {
                    precondition(overflow > 0, "Long target lists must overflow the scroll viewport")
                    scrollWheel(scroll, delta: -10_000)
                    try await Task.sleep(for: .milliseconds(200))
                    precondition(abs(scroll.documentVisibleRect.minY - overflow) < 1, "Scrolling down must reach Save mode")
                    scrollWheel(scroll, delta: 10_000)
                    try await Task.sleep(for: .milliseconds(200))
                    precondition(abs(scroll.documentVisibleRect.minY) < 1, "Scrolling up must reach the mode name again")
                }
                print("PASS: \(Int(size.width))x\(Int(size.height)), \(count) targets, viewport stays inside panel\(count >= 6 ? ", scrolls to both ends" : "")")
            }
        }
    }

    @MainActor private static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    @MainActor private static func scrollWheel(_ scroll: NSScrollView, delta: Int32) {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0)!
        scroll.scrollWheel(with: NSEvent(cgEvent: event)!)
    }
}
