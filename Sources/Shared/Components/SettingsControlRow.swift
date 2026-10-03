import SwiftUI

struct SettingsControlRow<Control: View>: View {
    let title: String
    let control: Control

    init(_ title: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 24) {
            Text(title).font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.primary.opacity(0.85))
            Spacer(minLength: 12)
            control.frame(width: 210, alignment: .trailing)
        }
    }
}
