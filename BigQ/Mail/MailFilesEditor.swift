import SwiftUI
import UniformTypeIdentifiers

struct MailFilesEditor: View {
    @Binding var files: [MailFileDraft]
    var onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(files) { file in
                HStack(spacing: 8) {
                    Label(file.fileName, systemImage: "paperclip")
                        .font(.callout)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button("Remove", systemImage: "minus.circle", role: .destructive) {
                        files.removeAll { $0.id == file.id }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Remove \(file.fileName)")
                }
            }
            Button("Add Attachment", systemImage: "paperclip", action: onAdd)
                .buttonStyle(.borderless)
                .help("Add a PDF or any other file")
            Text(MailFileLimits.note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension View {
    func mailFileImporter(
        isPresented: Binding<Bool>,
        files: Binding<[MailFileDraft]>,
        error: Binding<String?>
    ) -> some View {
        modifier(MailFileImporter(isPresented: isPresented, files: files, error: error))
    }
}

private struct MailFileImporter: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var files: [MailFileDraft]
    @Binding var error: String?

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $isPresented,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    let loaded = MailFileImport.load(urls: urls, existing: files)
                    files.append(contentsOf: loaded.files)
                    error = loaded.message
                case .failure(let failure):
                    let ns = failure as NSError
                    if ns.domain == NSCocoaErrorDomain, ns.code == NSUserCancelledError { return }
                    error = failure.localizedDescription
                }
            }
            .alert("Couldn’t add that file", isPresented: errorPresented) {
                Button("OK", role: .cancel) {}
                    .help("Dismiss")
            } message: {
                Text(error ?? "")
            }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }
}
