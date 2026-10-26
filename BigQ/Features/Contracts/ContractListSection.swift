import SwiftUI

struct ContractListSection: View {
    var contracts: [Contract]
    var emptyMessage: String

    @State private var reading: Contract?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Contracts", systemImage: "signature")
                .font(.headline)
            if contracts.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(contracts) { contract in
                    Button {
                        reading = contract
                    } label: {
                        ContractListRow(contract: contract)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(contract.displayTitle)")
                }
            }
        }
        .sheet(item: $reading) { contract in
            ContractReaderSheet(contract: contract)
        }
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
