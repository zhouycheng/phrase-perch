import SwiftUI

struct SnippetToolbarView: View {
    @Binding var displayMode: DisplayMode
    let displayName: String
    let addSnippet: () -> Void
    var body: some View {
        HStack {
            Picker("触发方式", selection: $displayMode) {
                Text("修饰键").tag(DisplayMode.modifierClick)
                Text("快捷键").tag(DisplayMode.shortcutOnly)
            }
            .pickerStyle(.menu).labelsHidden().frame(width: 100)
            .help("\(displayName) 的触发方式")
            .accessibilityLabel("\(displayName) 的触发方式")
            Spacer()
            Button(action: addSnippet) { Label("添加文案", systemImage: "plus") }
                .buttonStyle(.plain).font(.system(size: 12))
        }
        .foregroundStyle(.secondary).padding(.horizontal, EditorStyle.contentInset)
        .frame(height: EditorStyle.headerHeight)
    }
}
