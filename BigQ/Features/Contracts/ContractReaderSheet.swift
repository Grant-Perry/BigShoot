import SwiftData
import SwiftUI

struct ContractReaderSheet: View {
    @Environment(\.dismiss) private var dismiss
    var contract: Contract
    /// When set, shows Edit so a draft can jump straight into the composer.
    var onEdit: (() -> Void)?

    private var hasBody: Bool {
        ContractDocument.hasReadableBody(contract.html)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(contract.displayTitle)
                        .font(StudioDesign.displayTitle)
                    if !contextLine.isEmpty {
                        Text(contextLine)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let onEdit {
                    Button("Edit", systemImage: "pencil") {
                        dismiss()
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(50))
                            onEdit()
                        }
                    }
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(contract.signatures) { signature in
                    Text(signerLine(signature))
                        .textSelection(.enabled)
                }
            }

            document
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: hasBody ? 680 : nil)
    }

    @ViewBuilder
    private var document: some View {
        if hasBody {
            ScrollView {
                AgreementDocumentView(
                    html: contract.html,
                    agreementTitle: contract.displayTitle,
                    studioName: contract.job?.contact == nil
                        ? nil
                        : studioNameHint
                )
                .padding(28)
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: StudioDesign.Radius.row, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text("ShootQ stored this contract without the agreement text. The signature record above is what was exported.")
                .foregroundStyle(.secondary)
        }
    }

    /// Prefer an explicit studio line from the HTML; layout also detects photographer lines.
    private var studioNameHint: String? { nil }

    private var contextLine: String {
        [contract.job?.displayName, contract.eventLabel, contract.sentAt.map { "Sent \(StudioDay.string($0))" }]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func signerLine(_ signature: ContractSignature) -> String {
        let name = signature.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let who = name.isEmpty ? "Signer" : name
        guard signature.completed else { return "\(who) has not signed" }
        if let signedAt = signature.signedAt {
            return "\(who) signed \(StudioStamp.string(signedAt))"
        }
        return "\(who) signed"
    }
}
