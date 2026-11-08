import AppKit
import SwiftUI
import XCTest
@testable import PhrasePerch

@MainActor
final class MarkdownPreviewTests: PresentationTestCase {
    func testVisibleBodyModesAndDoubleClickInTheSwiftUIWindow() async throws {
        try requireVisibleUITests()
        let source = "# 可见检查\n\n双击 **正文位置** 进入编辑。\n\n| 名称 | 数据 |\n|---|---|\n| 内容 | 中文表格 |"
        var saved = source
        let root = NSHostingView(rootView: SnippetBodyEditorView(text: Binding(get: { saved }, set: { saved = $0 }), issue: nil)
            .padding(22).background(EditorStyle.background).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: CGRect(x: 150, y: 150, width: 340, height: 450),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Markdown 交互检查"
        window.contentView = root
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer { window.close() }
        root.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let body = try XCTUnwrap(descendants(root).compactMap { $0 as? SnippetBodyTextView.BodyView }.first)
        XCTAssertFalse(body.isEditing)
        let manager = try XCTUnwrap(body.preview.layoutManager)
        let container = try XCTUnwrap(body.preview.textContainer)
        manager.ensureLayout(for: container)
        let location = (body.preview.string as NSString).range(of: "正文位置").location
        let glyph = manager.glyphRange(forCharacterRange: NSRange(location: location, length: 1), actualCharacterRange: nil)
        let rect = manager.boundingRect(forGlyphRange: glyph, in: container)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
            location: body.preview.convert(CGPoint(x: rect.minX + 1, y: rect.midY), to: nil), modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 2, pressure: 1))
        window.sendEvent(event)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertTrue(body.isEditing)
        XCTAssertEqual(body.editor.selectedRange().location, (source as NSString).range(of: "正文位置").location)
        body.editor.insertText("新增", replacementRange: body.editor.selectedRange())
        XCTAssertTrue(saved.contains("**新增正文位置**"))
        body.setEditing(false)
        try await Task.sleep(for: .milliseconds(60))
        try savePreview(root, name: "markdown-visible-interaction.png")
    }

    func testBlocksAndInlineStylesPreserveTheirStructure() throws {
        let source = """
        # 标题

        **加粗**、*斜体*、~~删除~~ 与 [链接](https://example.com)

        1. 第一项
           - 嵌套项

        > 引用

        ```swift
        let n = 1
        ```

        | 名称 | 值 |
        |---|---|
        | 第一行 | 数据 |

        ![图片说明](https://example.com/image.png)
        """
        let document = MarkdownPreviewDocument(source: source)
        let text = document.text
        let string = text.string as NSString
        XCTAssertTrue(text.string.contains("标题\n"))
        XCTAssertTrue(text.string.contains("1.\t第一项\n•\t嵌套项"))
        XCTAssertTrue(text.string.contains("let n = 1"))
        XCTAssertTrue(text.string.contains("名称\n值\n第一行\n数据"))
        XCTAssertTrue(text.string.contains("图片说明"))
        XCTAssertFalse(text.string.contains("**"))
        XCTAssertFalse(text.string.contains("```"))
        let heading = try XCTUnwrap(text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertGreaterThan(heading.pointSize, 14)
        let bold = try XCTUnwrap(text.attribute(.font, at: string.range(of: "加粗").location, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: bold).contains(.boldFontMask))
        XCTAssertNotNil(text.attribute(.strikethroughStyle, at: string.range(of: "删除").location, effectiveRange: nil))
        XCTAssertEqual(text.attribute(.link, at: string.range(of: "链接").location, effectiveRange: nil) as? URL,
            URL(string: "https://example.com"))
        let cell = try XCTUnwrap(text.attribute(.paragraphStyle, at: string.range(of: "数据").location,
            effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertTrue(cell.textBlocks.first is NSTextTableBlock)
    }

    func testSourceMappingHandlesUnicodeEscapesEntitiesAndCode() {
        for (source, target) in [
            ("# 标题 😀\n\n正文 **中文内容**", "中文内容"),
            ("**同样文字** 再次 **同样文字**", "同样文字"),
            ("转义 \\* 之后 &amp; **最后文字**", "最后文字"),
            ("&#x1F600; **表情后面**", "表情后面"),
            ("正文 [链接文字](https://example.com)", "链接文字"),
            ("`&amp;\n最后文字`", "amp;"),
            ("`&amp;\n最后文字`", "最后文字"),
            ("```swift\nlet swift = 1\n```", "swift = 1"),
            ("```\n第一行\n未闭合代码", "未闭合代码"),
            ("````\n第一行\n```", "```"),
            ("    第一行\n    缩进代码", "缩进代码"),
            ("- 第一项\r\n- **第二项**", "第二项"),
            ("| 表头 |\n|---|\n| 表格内容 |", "表格内容"),
            ("**组合 e\u{301} 👩‍💻**", "👩‍💻"),
        ] {
            let document = MarkdownPreviewDocument(source: source)
            let visible = (document.text.string as NSString).range(of: target, options: .backwards)
            let original = (source as NSString).range(of: target, options: .backwards)
            XCTAssertNotEqual(visible.location, NSNotFound, source)
            guard visible.location != NSNotFound else { continue }
            for offset in 0..<visible.length {
                XCTAssertEqual(document.sourceOffset(at: visible.location + offset), original.location + offset, source)
            }
            for offset in 0...document.text.length {
                XCTAssertTrue((0...source.utf16.count).contains(document.sourceOffset(at: offset)), source)
            }
        }
        let escaped = MarkdownPreviewDocument(source: "前 \\* &amp; &#128512; 后")
        let string = escaped.text.string as NSString
        XCTAssertEqual(escaped.sourceOffset(at: string.range(of: "*").location), 3)
        XCTAssertEqual(escaped.sourceOffset(at: string.range(of: "&").location), 5)
        XCTAssertEqual(escaped.sourceOffset(at: string.range(of: "😀").location), 11)
        XCTAssertEqual(MarkdownPreviewDocument(source: "").sourceOffset(at: 100), 0)
    }

    func testDoubleClickEntersSourceAtTheClickedCharacterAndKeepsUndo() async throws {
        let source = "# 测试\n\n前面的 **中文定位 😀** 与 [链接](https://example.com)\n\n" + String(repeating: "其他段落\n\n", count: 30)
        let body = SnippetBodyTextView.BodyView(text: source, editing: false)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 340, height: 260),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = body
        defer { window.close() }
        body.layoutSubtreeIfNeeded()
        let preview = body.preview
        let manager = try XCTUnwrap(preview.layoutManager)
        let container = try XCTUnwrap(preview.textContainer)
        manager.ensureLayout(for: container)
        let visibleRange = (preview.string as NSString).range(of: "文定位")
        let glyphs = manager.glyphRange(forCharacterRange: NSRange(location: visibleRange.location, length: 1), actualCharacterRange: nil)
        let rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
        let local = CGPoint(x: rect.minX + 1, y: rect.midY)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
            location: preview.convert(local, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 2, pressure: 1))
        preview.mouseDown(with: event)
        XCTAssertTrue(body.isEditing)
        XCTAssertTrue(window.firstResponder === body.editor)
        let paragraph = try XCTUnwrap(body.editor.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(paragraph.lineSpacing, 4)
        XCTAssertEqual(body.editor.selectedRange(), NSRange(location: (source as NSString).range(of: "文定位").location, length: 0))
        body.editor.insertText("新增", replacementRange: body.editor.selectedRange())
        let edited = body.editor.string
        XCTAssertNotEqual(edited, source)
        body.setEditing(false)
        body.setEditing(true)
        body.editor.undoManager?.undo()
        XCTAssertEqual(body.editor.string, source)
        body.editor.undoManager?.redo()
        XCTAssertEqual(body.editor.string, edited)
        body.editor.setMarkedText("输入法文字", selectedRange: NSRange(location: 5, length: 0), replacementRange: body.editor.selectedRange())
        body.setEditing(false)
        XCTAssertFalse(body.editor.hasMarkedText())
        XCTAssertTrue(body.editor.string.contains("输入法文字"))
        XCTAssertTrue(body.preview.string.contains("输入法文字"))
    }

    func testPreviewFitsTheNarrowestBodyAndRendersAtWindowSizes() async throws {
        let source = "# 标题\n\n正文 **重点** 与 `inline`。\n\n> 一段引用\n\n- 第一项\n- 第二项\n\n```\n" + String(repeating: "长代码", count: 80)
            + "\n```\n\n| 名称 | 数据 |\n|---|---|\n| 第一项 | 一段可以换行的表格内容 |"
        let body = SnippetBodyTextView.BodyView(text: source, editing: false)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 256, height: 460),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = body
        defer { window.close() }
        body.layoutSubtreeIfNeeded()
        let manager = try XCTUnwrap(body.preview.layoutManager)
        let container = try XCTUnwrap(body.preview.textContainer)
        manager.ensureLayout(for: container)
        XCTAssertLessThanOrEqual(manager.usedRect(for: container).maxX, 257)
        try savePreview(body, name: "markdown-narrow-body.png")
        for size in [CGSize(width: 1070, height: 620), CGSize(width: 1280, height: 800), CGSize(width: 1440, height: 900)] {
            let store = ConfigurationRepository(storage: StubConfigurationStorage())
            for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(10)) }
            store.update {
                $0.profiles = [AppProfile(application: ApplicationIdentity(bundleIdentifier: "preview.markdown", fallbackBundlePath: nil),
                    displayName: "Markdown 示例", buttons: [Snippet(title: "Markdown 示例", text: source)])]
            }
            let saved = await store.flush()
            XCTAssertTrue(saved)
            let coordinator = ApplicationCoordinator(dependencies: AppDependencies(repository: store))
            defer { coordinator.stop() }
            let root = NSHostingView(rootView: makeMainWindowView(coordinator))
            let main = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
            main.isReleasedWhenClosed = false
            main.contentView = root
            main.appearance = NSAppearance(named: .darkAqua)
            root.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
            try savePreview(root, name: "markdown-window-\(Int(size.width)).png")
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            let split = try XCTUnwrap(descendants(root).compactMap { $0 as? WorkspaceSplitView.SplitView }.first)
            split.setPosition(5000, ofDividerAt: 1)
            split.setPosition(5000, ofDividerAt: 0)
            root.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertGreaterThanOrEqual(split.hosts[1].frame.width, 400)
            try savePreview(root, name: "markdown-sidebar-expanded-\(Int(size.width)).png")
            split.setPosition(-500, ofDividerAt: 0)
            split.setPosition(-500, ofDividerAt: 1)
            root.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertLessThanOrEqual(split.hosts[2].frame.width, 640)
            let expandedBody = try XCTUnwrap(descendants(split.hosts[2]).compactMap { $0 as? SnippetBodyTextView.BodyView }.first)
            XCTAssertEqual(expandedBody.bounds.width, split.hosts[2].bounds.width - 44, accuracy: 1)
            XCTAssertEqual(expandedBody.convert(expandedBody.bounds, to: split).maxX, split.hosts[2].frame.maxX - 22, accuracy: 1)
            try savePreview(root, name: "markdown-body-expanded-\(Int(size.width)).png")
            main.close()
        }
    }
}
