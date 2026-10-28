import SwiftUI

struct AboutView: View {
    let metadata: ApplicationMetadata

    var body: some View {
        HStack(spacing: 30) {
            Image(nsImage: metadata.icon)
                .resizable().interpolation(.high).frame(width: 128, height: 128)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("PhrasePerch").font(.system(size: 34, weight: .semibold))
                    Text("v\(metadata.version)").font(.system(size: 18)).foregroundStyle(.secondary)
                }
                Text("按应用管理快捷内容").font(.system(size: 16)).foregroundStyle(.secondary)

                HStack(spacing: 14) {
                    Link(destination: ApplicationMetadata.repositoryURL) {
                        Image(nsImage: NSImage(named: "GitHub") ?? NSImage()).renderingMode(.template)
                            .resizable().interpolation(.high).scaledToFit()
                            .frame(width: 24, height: 24)
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .help("GitHub 仓库").accessibilityLabel("GitHub 仓库")

                    Link(destination: ApplicationMetadata.authorEmailURL) {
                        Image(nsImage: NSImage(named: "Google") ?? NSImage()).renderingMode(.original)
                            .resizable().interpolation(.high).scaledToFit()
                            .frame(width: 24, height: 24)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .help("联系作者").accessibilityLabel("联系作者")

                    EditorStyle.separator.frame(width: 1, height: 16)

                    Link("问题反馈", destination: ApplicationMetadata.feedbackURL)
                    Link("更新日志", destination: ApplicationMetadata.releaseNotesURL)
                }
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .fixedSize()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EditorStyle.background)
    }
}
