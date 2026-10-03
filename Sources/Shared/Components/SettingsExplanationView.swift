import SwiftUI

struct SettingsExplanationView: View {
    let text: String
    var body: some View {

        Text(text).font(.system(size: 11, weight: .regular))
            .foregroundStyle(Color.primary.opacity(0.45))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}
