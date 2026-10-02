import AppKit
import Darwin

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
    private let reopenNotification = Notification.Name("local.FloatingInputBar.reopenSettings")
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard NSClassFromString("XCTestCase") == nil else { return }
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("local.FloatingInputBar.instance.lock")
            guard let descriptor = try acquireInstanceLock(at: url) else {
                DistributedNotificationCenter.default().postNotificationName(reopenNotification,
                    object: nil, userInfo: nil, deliverImmediately: true)
                NSApp.terminate(nil)
                return
            }
            instanceLock = descriptor
        } catch {
            let alert = NSAlert()
            alert.messageText = "PhrasePerch无法启动"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
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
                let alert = NSAlert(); alert.messageText = "配置尚未保存"
                alert.informativeText = "\(coordinator.store.errorMessage ?? "保存失败")。退出会丢失未保存草稿。"
                alert.addButton(withTitle: "保留草稿，取消退出"); alert.addButton(withTitle: "放弃草稿并退出")
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
application.setActivationPolicy(.accessory)
application.run()
