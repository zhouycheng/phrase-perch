import AppKit

@MainActor
struct MacOverlayInspector: OverlayInspecting {
    func hasOverlay(in frame: CGRect) -> Bool {
        guard
            let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return true }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let windows = raw.compactMap { entry -> VisibleOverlay? in
            guard let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                let level = entry[kCGWindowLayer as String] as? Int,
                let alpha = entry[kCGWindowAlpha as String] as? Double,
                let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { return nil }
            return VisibleOverlay(
                ownerPID: pid, layer: level,
                frame: CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height), alpha: alpha)
        }
        return hasForeignOverlay(
            windows, ownPID: getpid(),
            targetPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            menuFrame: frame, screens: NSScreen.screens.map(\.frame))
    }
}
