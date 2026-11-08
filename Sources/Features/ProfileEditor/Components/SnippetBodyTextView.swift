import AppKit
import SwiftUI

struct SnippetBodyTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isEditing: Bool

    func makeNSView(context: Context) -> BodyView {
        BodyView(text: text, editing: isEditing)
    }

    func updateNSView(_ view: BodyView, context: Context) {
        view.onTextChange = { text = $0 }
        view.onEditingChange = { isEditing = $0 }
        view.update(text: text, editing: isEditing)
    }

    final class BodyView: NSView, NSTextViewDelegate {
        let editor = SourceTextView()
        let preview = PreviewTextView()
        private let editorScroll = NSScrollView()
        private let previewScroll = NSScrollView()
        private var document: MarkdownPreviewDocument?
        private var previewSource: String?
        private(set) var isEditing: Bool
        var onTextChange: ((String) -> Void)?
        var onEditingChange: ((Bool) -> Void)?

        init(text: String, editing: Bool) {
            isEditing = editing
            super.init(frame: .zero)
            for (scroll, view) in [(editorScroll, editor), (previewScroll, preview)] {
                scroll.drawsBackground = false
                scroll.hasVerticalScroller = true
                scroll.autohidesScrollers = true
                scroll.scrollerStyle = .overlay
                scroll.borderType = .noBorder
                scroll.autoresizingMask = [.width, .height]
                view.drawsBackground = false
                view.isVerticallyResizable = true
                view.isHorizontallyResizable = false
                view.autoresizingMask = [.width]
                view.textContainerInset = .zero
                view.textContainer?.lineFragmentPadding = 0
                view.textContainer?.widthTracksTextView = true
                view.textContainer?.containerSize = CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
                scroll.documentView = view
                addSubview(scroll)
            }
            editor.isRichText = false
            editor.allowsUndo = true
            editor.isAutomaticQuoteSubstitutionEnabled = false
            editor.isAutomaticDashSubstitutionEnabled = false
            editor.isAutomaticTextReplacementEnabled = false
            editor.defaultParagraphStyle = EditorStyle.bodyTextAttributes[.paragraphStyle] as? NSParagraphStyle
            editor.typingAttributes = EditorStyle.bodyTextAttributes
            editor.font = .systemFont(ofSize: 14)
            editor.textColor = NSColor.labelColor.withAlphaComponent(0.85)
            editor.string = text
            editor.delegate = self
            editor.setAccessibilityLabel("文案正文")
            preview.isEditable = false
            preview.isSelectable = true
            preview.delegate = self
            preview.setAccessibilityLabel("Markdown 正文预览")
            preview.toolTip = "双击文字定位编辑；Command 点击打开链接"
            preview.onEdit = { [weak self] point in
                guard let self else { return }
                let offset = preview.characterIndexForInsertion(at: point)
                beginEditing(at: document?.sourceOffset(at: offset) ?? 0)
            }
            displayMode()
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            super.layout()
            editorScroll.frame = bounds
            previewScroll.frame = bounds
        }

        func update(text: String, editing: Bool) {
            if editor.string != text {
                editor.string = text
                editor.undoManager?.removeAllActions()
            }
            if editing != isEditing { setEditing(editing, notify: false) }
            else if !editing { refreshPreview() }
        }

        func setEditing(_ editing: Bool, notify: Bool = true) {
            if !editing {
                if editor.hasMarkedText() { editor.unmarkText() }
                onTextChange?(editor.string)
                if window?.firstResponder === editor, window?.makeFirstResponder(nil) == false {
                    DispatchQueue.main.async { [weak self] in self?.onEditingChange?(true) }
                    return
                }
            }
            isEditing = editing
            displayMode()
            if notify { onEditingChange?(editing) }
            if editing { window?.makeFirstResponder(editor) }
        }

        func beginEditing(at sourceOffset: Int) {
            setEditing(true)
            let length = editor.string.utf16.count
            let range = NSRange(location: min(length, max(0, sourceOffset)), length: 0)
            editor.setSelectedRange(range)
            editor.scrollRangeToVisible(range)
        }

        private func displayMode() {
            editorScroll.isHidden = !isEditing
            previewScroll.isHidden = isEditing
            if !isEditing { refreshPreview() }
        }

        private func refreshPreview() {
            guard previewSource != editor.string else { return }
            let document = MarkdownPreviewDocument(source: editor.string)
            self.document = document
            previewSource = editor.string
            preview.textStorage?.setAttributedString(document.text)
        }

        func textDidChange(_ notification: Notification) {
            guard notification.object as? NSTextView === editor else { return }
            onTextChange?(editor.string)
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            textView === preview && preview.handlingMouseDown
        }
    }

    final class SourceTextView: NSTextView {
        private let history = UndoManager()
        override var undoManager: UndoManager? { history }
    }

    final class PreviewTextView: NSTextView {
        var onEdit: ((CGPoint) -> Void)?
        private(set) var handlingMouseDown = false

        override func mouseDown(with event: NSEvent) {
            handlingMouseDown = true
            defer { handlingMouseDown = false }
            let point = convert(event.locationInWindow, from: nil)
            if event.modifierFlags.contains(.command) {
                let index = characterIndexForInsertion(at: point)
                if index < (textStorage?.length ?? 0),
                    let link = textStorage?.attribute(.link, at: index, effectiveRange: nil) as? URL {
                    NSWorkspace.shared.open(link)
                    return
                }
            }
            if event.clickCount == 2 { onEdit?(point); return }
            super.mouseDown(with: event)
        }
    }
}
