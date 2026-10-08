import SwiftUI

struct SnippetButtonView: View {
    let snippet: Snippet
    let selected: Bool
    let size: CGSize
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(floatingButtonTitle(snippet.title)).font(.system(size: snippetTitleFontSize, weight: .medium))
                .foregroundStyle(selected ? Color.black.opacity(0.9) : Color.white.opacity(0.8))
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .frame(width: size.width, height: size.height)
                .background(
                    Color(white: selected ? (hovering ? 0.98 : 0.92) : (hovering ? 0.42 : 0.32)),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12).strokeBorder(
                        selected ? Color.white : Color.clear, lineWidth: 2)
                )
                .opacity(snippet.isEnabled ? 1 : (selected ? 0.7 : 0.45))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
        .help(snippet.title).accessibilityLabel(snippet.title)
        .accessibilityValue(snippet.isEnabled ? "已启用" : "已停用")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
