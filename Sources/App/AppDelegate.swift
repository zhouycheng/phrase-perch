import AppKit
import Darwin

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: ApplicationCoordinator?
    private var instanceLock: Int32 = -1
    private var reopenObserver: NSObjectProtocol?
    private let reopenNotification = Notification.Name(
        "\(Bundle.main.bundleIdentifier ?? "local.FloatingInputBar").reopenSettings")
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard NSClassFromString("XCTestCase") == nil else { return }
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                "\(Bundle.main.bundleIdentifier ?? "local.FloatingInputBar").instance.lock")
            guard let descriptor = try SingleInstanceLock.acquire(at: url) else {
                DistributedNotificationCenter.default().postNotificationName(
                    reopenNotification,
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
        NSApp.mainMenu = ApplicationMenuBuilder.make()
        coordinator = ApplicationCoordinator()
        coordinator?.start()
        reopenObserver = DistributedNotificationCenter.default().addObserver(
            forName: reopenNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.coordinator?.openMainWindow() }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator?.openMainWindow()
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coordinator, coordinator.store.isReady else { return .terminateNow }
        if coordinator.restartExitReady { return .terminateNow }
        Task {
            let saved = await coordinator.store.flush()
            if saved {
                sender.reply(toApplicationShouldTerminate: true)
            } else {
                let alert = NSAlert()
                alert.messageText = "更改尚未保存"
                alert.informativeText = "\(coordinator.store.errorMessage ?? "保存失败")。退出后，未保存的更改将丢失。"
                alert.addButton(withTitle: "取消退出")
                alert.addButton(withTitle: "放弃更改并退出")
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
