import SwiftData
import SwiftUI

struct ContractReaderSheet: View {
    @Environment(\.dismiss) private var dismiss
    var contract: Contract
    @State private var agreement: AttributedString?

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
        .task(id: contract.persistentModelID) {
            guard hasBody else { return }
            agreement = ContractDocument.rendered(contract.html)
        }
    }

    @ViewBuilder
    private var document: some View {
        if let agreement {
            ScrollView {
                Text(agreement)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(28)
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: StudioDesign.Radius.row, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if hasBody {
            ProgressView("Opening the agreement")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text("ShootQ stored this contract without the agreement text. The signature record above is what was exported.")
                .foregroundStyle(.secondary)
        }
    }

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
