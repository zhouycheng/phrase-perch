import AppKit

@MainActor
final class InteractionStatusPanel {
    private let panel = FloatingMenuPanel(contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var task: Task<Void, Never>?
    init() {
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    func show(_ message: String, at point: CGPoint) {
        task?.cancel()
        guard !message.isEmpty else { panel.orderOut(nil); return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return }
        let safe = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        let view = content(message, maximumWidth: min(300, safe.width))
        panel.contentView = view
        panel.setFrame(Self.frame(size: view.frame.size, at: point, safe: safe), display: true)
        panel.orderFrontRegardless()
        task = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            self?.panel.orderOut(nil)
        }
    }
    static func frame(size: CGSize, at point: CGPoint, safe: CGRect) -> CGRect {
        var origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height - 12)
        if origin.y < safe.minY { origin.y = point.y + 12 }
        return CGRect(x: max(safe.minX, min(origin.x, safe.maxX - size.width)),
            y: max(safe.minY, min(origin.y, safe.maxY - size.height)), width: size.width, height: size.height)
    }
    func content(_ message: String, maximumWidth: CGFloat = 300) -> NSView {
        let font = NSFont.systemFont(ofSize: 12)
        let label = NSTextField(wrappingLabelWithString: message)
        label.textColor = .white
        label.font = font
        label.preferredMaxLayoutWidth = maximumWidth - 20
        let measured = label.fittingSize
        let width = min(maximumWidth, ceil(measured.width) + 20)
        let height = ceil(measured.height) + 14
        label.frame = CGRect(x: 10, y: 7, width: width - 20, height: height - 14)
        let view = NSView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.97).cgColor
        view.layer?.cornerRadius = 8
        view.layer?.borderWidth = 0.5
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        view.addSubview(label)
        return view
    }
}
