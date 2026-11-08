import AppKit

struct EditorColumns {
    static let windowSize = CGSize(width: 1070, height: 620)
    static let navigation: CGFloat = 68
    static let sidebarRange: ClosedRange<CGFloat> = 200...300
    static let editorRange: ClosedRange<CGFloat> = 300...640
    static let minimumContent: CGFloat = 400
    static let defaultSidebar: CGFloat = 200
    static let defaultEditor: CGFloat = 317
    let sidebar: CGFloat
    let ring: CGFloat
    let editor: CGFloat

    init(width: CGFloat, sidebar: CGFloat = Self.defaultSidebar, editor: CGFloat = Self.defaultEditor) {
        let available = max(Self.windowSize.width, width) - Self.navigation - 3
        var sidebar = sidebar.isFinite ? min(300, max(200, sidebar)) : Self.defaultSidebar
        var editor = editor.isFinite ? min(640, max(300, editor)) : Self.defaultEditor
        let shortage = max(0, sidebar + editor + Self.minimumContent - available)
        sidebar = max(Self.sidebarRange.lowerBound, sidebar - shortage)
        editor = min(editor, available - sidebar - Self.minimumContent)
        self.sidebar = sidebar
        self.editor = editor
        ring = available - sidebar - editor
    }
}
