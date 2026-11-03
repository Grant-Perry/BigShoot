import SwiftData
import SwiftUI

struct ContractListSection: View {
    var contracts: [Contract]
    var emptyMessage: String
    var onAdd: (() -> Void)?
    var onEdit: ((Contract) -> Void)?
    var onDelete: ((Contract) -> Void)?

    @State private var reading: Contract?
    @State private var pendingDelete: Contract?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Contracts", systemImage: "signature")
                    .font(.headline)
                Spacer()
                if let onAdd {
                    Button("Add Contract", systemImage: "plus", action: onAdd)
                        .help("Attach an agreement to this job")
                }
            }
            if contracts.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(contracts) { contract in
                    contractRow(contract)
                }
            }
        }
        .sheet(item: $reading) { contract in
            ContractReaderSheet(
                contract: contract,
                onEdit: canEdit(contract) ? {
                    reading = nil
                    onEdit?(contract)
                } : nil
            )
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Agreement", role: .destructive) {
                if let pendingDelete {
                    onDelete?(pendingDelete)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text(deleteMessage)
        }
    }

    @ViewBuilder
    private func contractRow(_ contract: Contract) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                reading = contract
            } label: {
                ContractListRow(contract: contract)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View \(contract.displayTitle)")

            VStack(spacing: 6) {
                if let onEdit, canEdit(contract) {
                    Button("Edit", systemImage: "pencil") {
                        onEdit(contract)
                    }
                    .help("Edit this agreement")
                }
                if onDelete != nil {
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        pendingDelete = contract
                    }
                    .help("Remove this agreement from the job")
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .fixedSize()
        }
        .contextMenu {
            Button("View", systemImage: "doc.richtext") {
                reading = contract
            }
            if let onEdit, canEdit(contract) {
                Button("Edit", systemImage: "pencil") {
                    onEdit(contract)
                }
            }
            if onDelete != nil {
                Divider()
                Button("Remove", systemImage: "trash", role: .destructive) {
                    pendingDelete = contract
                }
            }
        }
    }

    private func canEdit(_ contract: Contract) -> Bool {
        !contract.isSigned && contract.status.lowercased() != "sent"
    }

    private var deleteTitle: String {
        guard let pendingDelete else { return "Remove agreement?" }
        return "Remove “\(pendingDelete.displayTitle)”?"
    }

    private var deleteMessage: String {
        if pendingDelete?.isSigned == true {
            return "This agreement is signed. Removing it deletes the contract and its signature records from BigQ."
        }
        return "This removes the agreement from this job. It does not delete contract templates."
    }
}

private struct ContractListRow: View {
    var contract: Contract

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(contract.displayTitle)
                Spacer(minLength: 12)
                ContractStatusBadge(contract: contract)
            }
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text(signerLine)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        [contract.job?.displayName, contract.eventLabel]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var signerLine: String {
        let signed = contract.signatures.filter(\.completed).map(\.displayName).filter { !$0.isEmpty }
        if !signed.isEmpty {
            return "Signed by \(signed.joined(separator: ", "))"
        }
        let waiting = contract.signatures.map(\.displayName).filter { !$0.isEmpty }
        if waiting.isEmpty { return "No signer on file" }
        return "Waiting on \(waiting.joined(separator: ", "))"
    }
}

private struct ContractStatusBadge: View {
    var contract: Contract

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }

    private var title: String {
        switch contract.status.lowercased() {
        case "signed": "Signed"
        case "sent": "Sent"
        case "pending": "Pending"
        case "draft": "Draft"
        case "open": "Open"
        case "": contract.isSigned ? "Signed" : "Unsigned"
        default: contract.status.capitalized
        }
    }

    private var tint: Color {
        if contract.isSigned { return StudioDesign.paid }
        switch contract.status.lowercased() {
        case "sent", "pending", "open": return StudioDesign.gold
        default: return Color.secondary
        }
    }
}
