import SwiftUI

struct SettingsCardView<Content: View>: View {
    let title: String
    let symbol: String
    let badge: String
    let badgeColor: Color
    let content: Content

    init(
        title: String, symbol: String, badge: String, badgeColor: Color = .secondary,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.badge = badge
        self.badgeColor = badgeColor
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(.secondary)
                Text(title).font(.system(size: 16, weight: .semibold))
                Spacer()
                Text(badge).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(badgeColor.opacity(0.1), in: Capsule())
            }
            content
                .font(.system(size: 13, weight: .regular))
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.065), lineWidth: 1))
    }
}
