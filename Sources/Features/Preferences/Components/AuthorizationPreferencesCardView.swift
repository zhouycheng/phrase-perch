import SwiftUI

struct AuthorizationPreferencesCardView: View {
    @Bindable var viewModel: PreferencesViewModel
    var body: some View {
        SettingsCardView(title: "系统权限", symbol: "hand.raised", badge: "必需", badgeColor: .orange) {
            VStack(alignment: .leading, spacing: 13) {
                PermissionRowView(
                    step: viewModel.authorizationStep,
                    detail: viewModel.authorizationDetail,
                    isRestarting: viewModel.isRestarting,
                    action: viewModel.performAuthorizationAction)
                if !viewModel.mouseMonitorAvailable {
                    SettingsExplanationView(text: "鼠标触发暂不可用，仍可使用上方录制的快捷键。")
                }
            }
        }
    }
}
