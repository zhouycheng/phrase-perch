import SwiftUI

struct ProfileEditorView: View {
    @Bindable var viewModel: ProfileEditorViewModel
    let editorWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ProfileContentView(viewModel: viewModel)
            EditorStyle.separator.frame(width: 1)
            SnippetDetailView(viewModel: viewModel).frame(width: editorWidth)
        }
    }
}
