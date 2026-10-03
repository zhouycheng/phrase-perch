import AppKit
import Darwin

enum ApplicationMenuBuilder {
    @MainActor
    static func make() -> NSMenu {
        let menu = NSMenu()
        let applicationMenu = NSMenu(title: "PhrasePerch")
        let applicationItem = NSMenuItem()
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)
        let quit = NSMenuItem(
            title: "退出 PhrasePerch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        applicationMenu.addItem(quit)

        let editMenu = NSMenu(title: "编辑")
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        for (title, action, key, shifted) in [
            ("撤销", "undo:", "z", false), ("重做", "redo:", "z", true),
            ("剪切", "cut:", "x", false), ("复制", "copy:", "c", false),
            ("粘贴", "paste:", "v", false), ("全选", "selectAll:", "a", false),
        ] {
            if key == "x" { editMenu.addItem(.separator()) }
            let item = NSMenuItem(
                title: title, action: NSSelectorFromString(action),
                keyEquivalent: shifted ? key.uppercased() : key)
            item.keyEquivalentModifierMask = .command
            // A nil target routes each command to the focused native editor.
            editMenu.addItem(item)
        }
        return menu
    }
}
