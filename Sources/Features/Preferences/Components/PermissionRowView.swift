import SwiftUI

struct PermissionRowView: View {
    var step: AuthorizationFlow.Step
    var detail: String
    var isRestarting = false
    var action: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: step == .ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(step == .ready ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("辅助功能").font(.system(size: 13, weight: .medium))
                SettingsExplanationView(text: detail)
            }
            Spacer(minLength: 16)
            if step == .ready {
                Text(step.title).font(.system(size: 11, weight: .medium)).foregroundStyle(.green)
            } else {
                Button(isRestarting ? "正在重启…" : step.title, action: action).disabled(isRestarting)
                    .buttonStyle(.borderedProminent).tint(.orange)
            }
        }
    }
}
