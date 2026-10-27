import AppKit
import CoreServices
import ServiceManagement

@MainActor
final class MacAppEntryController: NSObject, AppEntryPlatform {
    private(set) var statusItem: NSStatusItem?
    private(set) var statusMenu: NSMenu?
    private var onToggle: (() -> Void)?
    private var onOpen: (() -> Void)?
    private var onImport: (() -> Void)?
    private var onExport: (() -> Void)?
    var dockVisible: Bool { NSApp.activationPolicy() == .regular }
    var loginEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func wasLaunchedAtLogin(_ event: NSAppleEventDescriptor?) -> Bool {
        event?.eventID == AEEventID(kAEOpenApplication)
            && event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }
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
            refreshMenu(enabled: enabled)
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            let image = NSImage(named: "MenuBarIcon")
                ?? NSImage(systemSymbolName: "text.quote", accessibilityDescription: "PhrasePerch")
            image?.size = NSSize(width: 22, height: 22)
            image?.isTemplate = true
            image?.accessibilityDescription = "PhrasePerch"
            item.button?.image = image
            item.button?.target = self
            item.button?.action = #selector(statusItemClicked)
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            item.button?.toolTip = "打开 PhrasePerch，右键查看更多操作"
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
            statusMenu = menu
            statusItem = item
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
            statusMenu = nil
        }
    }
    func refreshMenu(enabled: Bool) { statusMenu?.items.first?.state = enabled ? .on : .off }
    func stop() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        statusMenu = nil
    }
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            statusMenu?.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY), in: sender)
        } else { onOpen?() }
    }
    @objc private func toggleEnabled() { onToggle?() }
    @objc private func openMainWindow() { onOpen?() }
    @objc private func importConfiguration() { onImport?() }
    @objc private func exportConfiguration() { onExport?() }
    @objc private func quit() { NSApp.terminate(nil) }
}
