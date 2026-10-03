import AppKit

final class AuthorizationGuideView: AuthorizationBackdrop {
    var onClose: (() -> Void)?
    var onDragEnded: ((Bool) -> Void)?
    init(applicationURL: URL, frame: CGRect) {
        super.init(frame: CGRect(origin: .zero, size: frame.size))
        self.frame = CGRect(origin: .zero, size: frame.size)
        self.material = .popover
        self.state = .active
        self.blendingMode = .behindWindow
        self.appearance = NSAppearance(named: .darkAqua)
        self.wantsLayer = true
        self.layer?.cornerRadius = 14
        self.layer?.masksToBounds = true
        let label = NSTextField(wrappingLabelWithString: "将下方应用拖入授权列表，然后开启开关。")
        label.frame = CGRect(x: 16, y: 66, width: frame.width - 52, height: 32)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        self.addSubview(label)
        let drag = ApplicationDragView(
            applicationURL: applicationURL,
            frame: CGRect(x: 16, y: 12, width: frame.width - 32, height: 44))
        drag.onDragEnded = { [weak self] accepted in
            if accepted { self?.onClose?() }
            self?.onDragEnded?(accepted)
        }
        self.addSubview(drag)
        let close = NonactivatingButton(frame: CGRect(x: frame.width - 28, y: 80, width: 18, height: 20))
        close.title = "×"
        close.isBordered = false
        close.target = self
        close.action = #selector(closeGuide)
        close.setAccessibilityLabel("关闭拖拽提示")
        self.addSubview(close)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func closeGuide() { onClose?() }
}
