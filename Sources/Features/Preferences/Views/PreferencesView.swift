import SwiftUI

struct PreferencesView: View {
    @Bindable var viewModel: PreferencesViewModel
    let requestRecovery: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeaderView(title: "设置", subtitle: "管理快捷栏、系统权限和启动方式")

                TriggerPreferencesCardView(viewModel: viewModel)

                TitleGenerationPreferencesCardView(viewModel: viewModel)

                AuthorizationPreferencesCardView(viewModel: viewModel)

                AppEntryPreferencesCardView(viewModel: viewModel)

                ConfigurationPreferencesCardView(viewModel: viewModel, requestRecovery: requestRecovery)
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
