import SwiftUI

struct PermissionSetupView: View {
    let requirements: [PermissionRequirement]
    let isRestarting: Bool
    let feedback: String
    var onAction: (String) -> Void
    var onClose: () -> Void

    private var currentRequirement: PermissionRequirement? {
        requirements.first { $0.needsAttention && $0.actionTitle != nil }
    }
    private var title: String {
        guard let currentRequirement else { return "已准备就绪" }
        return currentRequirement.status == .pending ? "重启即可使用" : "开启\(currentRequirement.title)"
    }
    private var actionHint: String {
        guard let currentRequirement else { return "可以开始使用 PhrasePerch 了" }
        return currentRequirement.status == .pending ? "让已开启的权限生效" : "将前往系统设置"
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable()
                .interpolation(.high)
                .frame(width: 80, height: 80)
                .accessibilityHidden(true)
                .padding(.bottom, 18)

            Text(title)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .padding(.bottom, 10)
            Text("让 PhrasePerch 将你选择的内容\n填入输入框")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(requirements) { requirement in
                        HStack(spacing: 12) {
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(.blue.gradient, in: RoundedRectangle(cornerRadius: 8))
                                .accessibilityHidden(true)
                            Text(requirement.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                            Spacer(minLength: 8)
                            Text(requirement.status.rawValue)
                                .font(.system(size: 12))
                                .foregroundStyle(requirement.needsAttention ? .white.opacity(0.55) : .green)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(EditorStyle.separator, lineWidth: 1))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(height: CGFloat(min(requirements.count, 3)) * 56 - (requirements.isEmpty ? 0 : 8))
            .padding(.bottom, 16)

            Button {
                if let currentRequirement { onAction(currentRequirement.id) } else { onClose() }
            } label: {
                Text(isRestarting ? "正在重启…" : (currentRequirement?.actionTitle ?? "开始使用"))
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .foregroundStyle(.white)
                    .background(.blue.gradient, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.15), lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(isRestarting)
            .opacity(isRestarting ? 0.6 : 1)
            .frame(maxWidth: 264)
            .padding(.bottom, 8)

            Text(actionHint)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
            if !feedback.isEmpty {
                Text(feedback)
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
            Button(currentRequirement == nil ? "关闭" : "稍后", action: onClose)
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.65))
                .keyboardShortcut(.cancelAction)
                .padding(.top, 20)
        }
        .frame(maxWidth: 364)
        .padding(.horizontal, 48)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Color(white: 0.155), Color(white: 0.12)],
            startPoint: .topLeading, endPoint: .bottomTrailing))
        .preferredColorScheme(.dark)
    }
}
