import SwiftUI

struct NavigationRailView: View {
    @Binding var page: MainPage
    var body: some View {
        VStack(spacing: 12) {
            ForEach(MainPage.allCases, id: \.self) { item in
                Button {
                    page = item
                } label: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(page == item ? Color.primary : Color.secondary)
                        .frame(width: 44, height: 44)
                        .background(
                            page == item ? Color.white.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 13)
                        )
                        .frame(width: EditorColumns.navigation)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help(item.title).accessibilityLabel(item.title)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
        .frame(width: EditorColumns.navigation)
        .frame(maxHeight: .infinity)
    }
}
