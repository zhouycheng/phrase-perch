import SwiftUI

struct AttachmentEditorView: View {
    @Bindable var viewModel: ProfileEditorViewModel
    let file: AttachmentReference

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("附件", systemImage: "paperclip").font(.caption).foregroundStyle(.secondary)
            Text(file.fileName).font(.body).textSelection(.enabled)
            Text(ByteCountFormatter.string(fromByteCount: file.byteCount, countStyle: .file))
                .font(.caption).foregroundStyle(.secondary)
            if viewModel.attachmentAvailable == false {
                Label("文件不可用，请重新选择", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            } else { Text("已保存文件副本").font(.caption).foregroundStyle(.secondary) }
            Button("替换附件", action: viewModel.replaceAttachment).disabled(viewModel.isImportingAttachment)
            if viewModel.isImportingAttachment { ProgressView("正在保存附件…").controlSize(.small) }
            if let message = viewModel.attachmentMessage { Text(message).font(.caption).foregroundStyle(.orange) }
            Text("从快捷菜单选择，即可粘贴到支持附件的输入框。")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: file) { await viewModel.checkAttachment(file) }
    }
}
