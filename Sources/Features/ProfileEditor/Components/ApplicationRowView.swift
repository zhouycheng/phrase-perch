import SwiftUI

struct ApplicationRowView: View {
    let profile: AppProfile
    let selected: Bool
    @Binding var enabled: Bool
    let select: () -> Void
    let duplicate: () -> Void
    let requestDelete: () -> Void
    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                select()
            } label: {
                HStack(spacing: 10) {
                    Image(nsImage: ApplicationCatalog.icon(at: profile.lastKnownBundlePath ?? ""))
                        .resizable().frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.displayName).font(.system(size: 13)).lineLimit(1)
                        Text("\(profile.buttons.count) 条文案")
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 10).padding(.trailing, 34)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("选择应用 \(profile.displayName)").help(profile.displayName)
            Toggle("启用 \(profile.displayName)", isOn: $enabled)
                .toggleStyle(.checkbox).labelsHidden().help("启用或停用此应用")
                .padding(.trailing, 10)
        }
        .background(
            selected ? EditorStyle.selectedRow : .clear,
            in: RoundedRectangle(cornerRadius: 10)
        )
        .contextMenu {
            Button("以此创建一个配置", action: duplicate)
            Button("移除应用…", role: .destructive) { requestDelete() }
        }
    }
}
