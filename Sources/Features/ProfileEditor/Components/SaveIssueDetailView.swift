import SwiftUI

struct SaveIssueDetailView: View {
    let message: String
    let retry: () -> Void
    let openConfiguration: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message).textSelection(.enabled)
            HStack {
                Button("重试保存", action: retry)
                Button("配置设置", action: openConfiguration)
            }
        }
        .font(.callout).padding(16).frame(width: 300)
    }
}
