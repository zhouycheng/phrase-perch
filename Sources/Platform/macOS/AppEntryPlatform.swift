import Foundation

@MainActor
protocol AppEntryPlatform: AnyObject {
    var dockVisible: Bool { get }
    var loginEnabled: Bool { get }
    func setDockVisible(_ visible: Bool)
    func setLoginEnabled(_ enabled: Bool) throws
    func setMenuBar(
        visible: Bool, enabled: Bool, toggle: @escaping () -> Void, open: @escaping () -> Void,
        importFile: @escaping () -> Void, exportFile: @escaping () -> Void)
    func refreshMenu(enabled: Bool)
    func stop()
}
