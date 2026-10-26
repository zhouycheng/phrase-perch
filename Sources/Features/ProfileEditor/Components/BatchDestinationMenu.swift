import SwiftUI

struct BatchDestinationMenu: View {
    @Bindable var viewModel: ProfileEditorViewModel
    let profile: AppProfile
    let group: UUID?
    let copying: Bool

    var body: some View {
        Button(group == nil ? "应用根级" : "此分组") {
            viewModel.transferSelection(to: profile.id, group: group, copying: copying)
        }
        .disabled(!viewModel.canTransferSelection(to: profile, group: group, copying: copying))
        ForEach(profile.children(of: group).filter { $0.kind == .group }) { node in
            Menu(profile.title(of: node)) {
                AnyView(BatchDestinationMenu(viewModel: viewModel, profile: profile, group: node.id, copying: copying))
            }
        }
    }
}
