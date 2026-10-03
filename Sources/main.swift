import AppKit
import Darwin

@MainActor
func makeApplicationMenu() -> NSMenu {
    let menu = NSMenu()
    let applicationMenu = NSMenu(title: "PhrasePerch")
    let applicationItem = NSMenuItem()
    applicationItem.submenu = applicationMenu
    menu.addItem(applicationItem)
    let quit = NSMenuItem(title: "退出 PhrasePerch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    quit.target = NSApp
    applicationMenu.addItem(quit)

    let editMenu = NSMenu(title: "编辑")
    let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
    editItem.submenu = editMenu
    menu.addItem(editItem)
    for (title, action, key, shifted) in [
        ("撤销", "undo:", "z", false), ("重做", "redo:", "z", true),
        ("剪切", "cut:", "x", false), ("复制", "copy:", "c", false),
        ("粘贴", "paste:", "v", false), ("全选", "selectAll:", "a", false)
    ] {
        if key == "x" { editMenu.addItem(.separator()) }
        let item = NSMenuItem(title: title, action: NSSelectorFromString(action),
                              keyEquivalent: shifted ? key.uppercased() : key)
        item.keyEquivalentModifierMask = .command
        // A nil target routes each command to the focused native editor.
        editMenu.addItem(item)
    }
    return menu
}

func acquireInstanceLock(at url: URL) throws -> Int32? {
    let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return descriptor }
    let code = errno
    close(descriptor)
    if code == EWOULDBLOCK { return nil }
    throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var instanceLock: Int32 = -1
    private var reopenObserver: NSObjectProtocol?
    private let reopenNotification = Notification.Name("\(Bundle.main.bundleIdentifier ?? "local.FloatingInputBar").reopenSettings")
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard NSClassFromString("XCTestCase") == nil else { return }
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(Bundle.main.bundleIdentifier ?? "local.FloatingInputBar").instance.lock")
            guard let descriptor = try acquireInstanceLock(at: url) else {
                DistributedNotificationCenter.default().postNotificationName(reopenNotification,
                    object: nil, userInfo: nil, deliverImmediately: true)
                NSApp.terminate(nil)
                return
            }
            instanceLock = descriptor
        } catch {
            let alert = NSAlert()
            alert.messageText = "PhrasePerch 无法启动"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        NSApp.mainMenu = makeApplicationMenu()
        coordinator = AppCoordinator(); coordinator?.start()
        reopenObserver = DistributedNotificationCenter.default().addObserver(forName: reopenNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.coordinator?.openSettings() }
            }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator?.openSettings()
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coordinator, coordinator.store.isReady else { return .terminateNow }
        if coordinator.restartExitReady { return .terminateNow }
        Task {
            let saved = await coordinator.store.flush()
            if saved { sender.reply(toApplicationShouldTerminate: true) }
            else {
                let alert = NSAlert(); alert.messageText = "更改尚未保存"
                alert.informativeText = "\(coordinator.store.errorMessage ?? "保存失败")。退出后，未保存的更改将丢失。"
                alert.addButton(withTitle: "取消退出"); alert.addButton(withTitle: "放弃更改并退出")
                sender.reply(toApplicationShouldTerminate: alert.runModal() == .alertSecondButtonReturn)
            }
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
        if let reopenObserver { DistributedNotificationCenter.default().removeObserver(reopenObserver) }
        if instanceLock >= 0 { close(instanceLock) }
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
let entryVisibility = AppEntryVisibility.load()
application.setActivationPolicy(entryVisibility.dock ? .regular : .accessory)
application.run()
