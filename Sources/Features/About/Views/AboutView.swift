import SwiftUI

struct AboutView: View {
    let metadata: ApplicationMetadata

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: metadata.icon)
                .resizable().interpolation(.high).frame(width: 112, height: 112)
            Text("PhrasePerch").font(.largeTitle.weight(.semibold))
            Text("按应用管理快捷文案").font(.callout).foregroundStyle(.secondary)
            Text("v\(metadata.version)").font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
