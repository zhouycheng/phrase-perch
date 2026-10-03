import SwiftUI

struct EmptyStateView: View {
    let title: String
    let symbol: String
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(.secondary)
            if let action {
                Button(title, action: action).buttonStyle(.borderless)
            } else {
                Text(title).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
