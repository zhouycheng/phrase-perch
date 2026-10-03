import AppKit
import ServiceManagement

@MainActor
final class MacAppEntryController: NSObject, AppEntryPlatform {
    private var statusItem: NSStatusItem?
    private var onToggle: (() -> Void)?
    private var onOpen: (() -> Void)?
    private var onImport: (() -> Void)?
    private var onExport: (() -> Void)?
    var dockVisible: Bool { NSApp.activationPolicy() == .regular }
    var loginEnabled: Bool { SMAppService.mainApp.status == .enabled }
    func setDockVisible(_ visible: Bool) { _ = NSApp.setActivationPolicy(visible ? .regular : .accessory) }
    func setLoginEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
    func setMenuBar(
        visible: Bool, enabled: Bool, toggle: @escaping () -> Void, open: @escaping () -> Void,
        importFile: @escaping () -> Void, exportFile: @escaping () -> Void
    ) {
        onToggle = toggle
        onOpen = open
        onImport = importFile
        onExport = exportFile
        if visible {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "text.quote", accessibilityDescription: "PhrasePerch")
            let menu = NSMenu()
            menu.addItem(withTitle: "启用／暂停", action: #selector(toggleEnabled), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "打开 PhrasePerch", action: #selector(openMainWindow), keyEquivalent: ",")
            menu.addItem(withTitle: "导入配置…", action: #selector(importConfiguration), keyEquivalent: "")
            menu.addItem(withTitle: "导出配置…", action: #selector(exportConfiguration), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "q")
            for entry in menu.items { entry.target = self }
            menu.items.first?.state = enabled ? .on : .off
            item.menu = menu
            statusItem = item
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }
    func refreshMenu(enabled: Bool) { statusItem?.menu?.items.first?.state = enabled ? .on : .off }
    func stop() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }
    @objc private func toggleEnabled() { onToggle?() }
    @objc private func openMainWindow() { onOpen?() }
    @objc private func importConfiguration() { onImport?() }
    @objc private func exportConfiguration() { onExport?() }
    @objc private func quit() { NSApp.terminate(nil) }
}
