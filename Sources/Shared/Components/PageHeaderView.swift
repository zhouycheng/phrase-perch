import SwiftUI

struct PageHeaderView: View {
    let title: String
    let subtitle: String
    var body: some View {

        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 24, weight: .semibold))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}
