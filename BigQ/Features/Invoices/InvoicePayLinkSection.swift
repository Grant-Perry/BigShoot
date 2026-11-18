import AppKit
import SwiftData
import SwiftUI

@MainActor
@Observable
final class PayLinkModel {
    var message = ""
    var isWorking = false
    private(set) var copied = false

    func publish(_ invoice: Invoice, in context: ModelContext) async {
        await run(invoice, in: context, create: true)
    }

    func refresh(_ invoice: Invoice, in context: ModelContext) async {
        guard !invoice.payToken.isEmpty || invoice.canRecordPayment else { return }
        await run(invoice, in: context, create: false)
    }

    private func run(_ invoice: Invoice, in context: ModelContext, create: Bool) async {
        guard !isWorking else { return }
        guard let studioKey = PayStudioKey.load() else {
            message = PayLinkError.notConfigured.localizedDescription
            return
        }
        if create { isWorking = true }
        copied = false
        defer { if create { isWorking = false } }
        let invoiceId = ensureArchiveID(on: invoice, in: context)
        let api = PayAPI(baseURL: PayAPI.liveBase, studioKey: studioKey)
        do {
            let snapshot: PayLinkSnapshot
            if create {
                snapshot = try await api.publish(
                    invoiceId: invoiceId,
                    number: invoice.displayNumber,
                    amount: PayMoney.wire(invoice.balance),
                    billToName: invoice.clientName,
                    studioName: invoice.studio?.displayName ?? StudioBrand.defaultName
                )
            } else {
                snapshot = try await api.status(invoiceId: invoiceId)
            }
            invoice.payToken = snapshot.token
            try context.save()
            if snapshot.isPaid {
                try record(snapshot, on: invoice, in: context)
                message = "Paid online."
                return
            }
            if create {
                copy(snapshot.url)
                message = "Pay link copied."
            } else if message.isEmpty {
                message = "Waiting for the client."
            }
        } catch let error as PayLinkError {
            if case .server("No pay link yet.") = error, !create {
                return
            }
            message = error.localizedDescription
        } catch {
            message = error.localizedDescription
        }
    }

    private func record(_ snapshot: PayLinkSnapshot, on invoice: Invoice, in context: ModelContext) throws {
        guard let amount = snapshot.chargedAmount, amount > 0 else { return }
        let methodName = snapshot.cardLabel.isEmpty ? PaymentMethod.card.title : snapshot.cardLabel
        try PayLedger.apply(
            amount: amount,
            paidAt: snapshot.paidDate ?? .now,
            methodKey: PaymentMethod.card.rawValue,
            methodName: methodName,
            transactionID: snapshot.transactionId,
            to: invoice,
            in: context
        )
    }

    private func ensureArchiveID(on invoice: Invoice, in context: ModelContext) -> String {
        let trimmed = invoice.archiveID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let assigned = UUID().uuidString
        invoice.archiveID = assigned
        try? context.save()
        return assigned
    }

    private func copy(_ url: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        copied = true
    }

    func copyAgain(_ invoice: Invoice) {
        guard !invoice.payToken.isEmpty else { return }
        copy(payURL(invoice.payToken).absoluteString)
        message = "Pay link copied."
    }
}

private func payURL(_ token: String) -> URL {
    PayAPI.liveBase.appendingPathComponent("pay").appendingPathComponent(token)
}

struct InvoicePayLinkSection: View {
    var invoice: Invoice

    @Environment(\.modelContext) private var modelContext
    @State private var model = PayLinkModel()

    var body: some View {
        if invoice.canRecordPayment || !invoice.payToken.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Card payment")
                    .font(.headline)
                StudioLabeledStack {
                    if !invoice.payToken.isEmpty {
                        StudioLabeledRow("Pay link") {
                            Text(payURL(invoice.payToken).absoluteString)
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                    }
                    if !model.message.isEmpty {
                        StudioLabeledRow("Status") {
                            Text(model.message)
                                .foregroundStyle(model.message == "Paid online." ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                        }
                    }
                }
                HStack {
                    if invoice.canRecordPayment {
                        Button(invoice.payToken.isEmpty ? "Create pay link" : "Update pay link") {
                            Task { await model.publish(invoice, in: modelContext) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isWorking)
                    }
                    if !invoice.payToken.isEmpty {
                        Button("Copy link") { model.copyAgain(invoice) }
                            .buttonStyle(.bordered)
                            .disabled(model.isWorking)
                    }
                    if model.isWorking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .padding(StudioDesign.Spacing.card)
            .paperCard()
            .task(id: invoice.payToken) {
                guard !invoice.payToken.isEmpty else { return }
                while !Task.isCancelled {
                    await model.refresh(invoice, in: modelContext)
                    if !invoice.canRecordPayment { return }
                    try? await Task.sleep(for: .seconds(15))
                }
            }
        }
    }
}
