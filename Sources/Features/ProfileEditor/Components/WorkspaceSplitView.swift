import AppKit
import SwiftUI

struct WorkspaceSplitView: NSViewRepresentable {
    let sidebar: AnyView
    let content: AnyView
    let detail: AnyView
    var defaults: UserDefaults? = .standard

    func makeNSView(context: Context) -> SplitView { SplitView(defaults: defaults) }

    func updateNSView(_ view: SplitView, context: Context) {
        for (host, root) in zip(view.hosts, [sidebar, content, detail]) {
            host.rootView = AnyView(root.environment(\.self, context.environment))
        }
    }

    final class SplitView: NSSplitView, NSSplitViewDelegate {
        static let sidebarKey = "PhrasePerch.workspace.sidebarWidth"
        static let editorKey = "PhrasePerch.workspace.editorWidth"
        let hosts = (0..<3).map { _ in NSHostingView(rootView: AnyView(EmptyView())) }
        private let defaults: UserDefaults?
        private var sidebarWidth: CGFloat
        private var editorWidth: CGFloat
        private var arranging = false

        init(defaults: UserDefaults?) {
            self.defaults = defaults
            sidebarWidth = (defaults?.object(forKey: Self.sidebarKey) as? NSNumber)?.doubleValue ?? EditorColumns.defaultSidebar
            editorWidth = (defaults?.object(forKey: Self.editorKey) as? NSNumber)?.doubleValue ?? EditorColumns.defaultEditor
            super.init(frame: CGRect(x: 0, y: 0, width: 1001, height: 620))
            isVertical = true
            dividerStyle = .thin
            delegate = self
            setAccessibilityLabel("应用与快捷内容分栏")
            for host in hosts {
                host.sizingOptions = []
                addArrangedSubview(host)
            }
            arrange()
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override var dividerThickness: CGFloat { bounds.width >= 2 ? 1 : 0 }
        override var dividerColor: NSColor { NSColor.white.withAlphaComponent(0.13) }

        private func arrange() {
            guard !arranging, arrangedSubviews.count == 3 else { return }
            arranging = true
            defer { arranging = false }
            guard bounds.width >= EditorColumns.windowSize.width - EditorColumns.navigation - 1, bounds.height > 0 else {
                // SwiftUI can propose zero bounds before the window receives its final size.
                let width = max(0, (bounds.width - 2 * dividerThickness) / 3)
                for (index, host) in hosts.enumerated() {
                    host.frame = CGRect(x: CGFloat(index) * (width + dividerThickness), y: 0,
                        width: width, height: bounds.height)
                }
                return
            }
            let columns = EditorColumns(width: bounds.width + EditorColumns.navigation + 1,
                sidebar: sidebarWidth, editor: editorWidth)
            sidebarWidth = columns.sidebar
            editorWidth = columns.editor
            var x: CGFloat = 0
            for (host, width) in zip(hosts, [columns.sidebar, columns.ring, columns.editor]) {
                host.frame = CGRect(x: x, y: 0, width: width, height: bounds.height)
                x += width + dividerThickness
            }
        }

        func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) { arrange() }

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int) -> CGFloat {
            max(proposedMinimumPosition, dividerIndex == 0 ? EditorColumns.sidebarRange.lowerBound
                : max(sidebarWidth + 1 + EditorColumns.minimumContent, bounds.width - 1 - EditorColumns.editorRange.upperBound))
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int) -> CGFloat {
            min(proposedMaximumPosition, dividerIndex == 0
                ? min(EditorColumns.sidebarRange.upperBound, bounds.width - 2 - editorWidth - EditorColumns.minimumContent)
                : bounds.width - 1 - EditorColumns.editorRange.lowerBound)
        }

        func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool { false }

        func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect,
            forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
            drawnRect.insetBy(dx: -3.5, dy: 0)
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            guard !arranging, hosts.count == 3,
                bounds.width >= EditorColumns.windowSize.width - EditorColumns.navigation - 1, bounds.height > 0 else { return }
            sidebarWidth = hosts[0].frame.width
            editorWidth = hosts[2].frame.width
            defaults?.set(sidebarWidth, forKey: Self.sidebarKey)
            defaults?.set(editorWidth, forKey: Self.editorKey)
        }
    }
}
