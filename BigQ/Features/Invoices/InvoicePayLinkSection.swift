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
                    amount: PayMoney.wire(PayLinkAmount.forInvoice(invoice)),
                    billToName: invoice.clientName,
                    studioName: invoice.studio?.displayName ?? StudioBrand.defaultName
                )
            } else {
                snapshot = try await api.status(invoiceId: invoiceId)
            }
            invoice.payToken = snapshot.token
            try context.save()
            let applied = try record(snapshot, on: invoice, in: context)
            if snapshot.isPaid {
                message = "Paid online."
                return
            }
            if applied > 0 {
                message = "Recorded \(StudioMoney.string(applied))."
                return
            }
            if create {
                copy(snapshot.url)
                message = "Pay link copied for \(StudioMoney.string(PayLinkAmount.forInvoice(invoice)))."
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

    @discardableResult
    private func record(_ snapshot: PayLinkSnapshot, on invoice: Invoice, in context: ModelContext) throws -> Decimal {
        var applied: Decimal = 0
        for payment in snapshot.recordedPayments {
            guard let amount = payment.chargedAmount, amount > 0 else { continue }
            let methodName = payment.cardLabel.isEmpty ? PaymentMethod.card.title : payment.cardLabel
            let result = try PayLedger.apply(
                amount: amount,
                paidAt: payment.paidDate ?? .now,
                methodKey: PaymentMethod.card.rawValue,
                methodName: methodName,
                transactionID: payment.transactionId,
                to: invoice,
                in: context
            )
            if !result.alreadyRecorded { applied += amount }
        }
        return applied
    }

    func publishQuote(_ quote: Quote, in context: ModelContext) async {
        guard PayLinkAmount.forQuote(quote) > 0 else {
            message = "Add an amount before creating a pay link."
            return
        }
        guard !isWorking else { return }
        guard let studioKey = PayStudioKey.load() else {
            message = PayLinkError.notConfigured.localizedDescription
            return
        }
        isWorking = true
        defer { isWorking = false }
        let quoteId = ensureArchiveID(on: quote, in: context)
        let api = PayAPI(baseURL: PayAPI.liveBase, studioKey: studioKey)
        do {
            let snapshot = try await api.publish(
                invoiceId: quoteId,
                number: quote.displayNumber,
                amount: PayMoney.wire(PayLinkAmount.forQuote(quote)),
                billToName: quote.clientName,
                studioName: quote.studio?.displayName ?? StudioBrand.defaultName
            )
            quote.payToken = snapshot.token
            try context.save()
            copy(snapshot.url)
            message = "Pay link copied for \(StudioMoney.string(PayLinkAmount.forQuote(quote)))."
        } catch {
            message = error.localizedDescription
        }
    }

    private func ensureArchiveID(on quote: Quote, in context: ModelContext) -> String {
        let trimmed = quote.archiveID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let assigned = UUID().uuidString
        quote.archiveID = assigned
        try? context.save()
        return assigned
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

struct QuotePayLinkButton: View {
    var quote: Quote

    @Environment(\.modelContext) private var modelContext
    @State private var model = PayLinkModel()
    @State private var showResult = false

    var body: some View {
        if quote.total > 0 && quote.status != .void {
            Button(quote.payToken.isEmpty ? "Create pay link" : "Copy pay link", systemImage: "link") {
                Task {
                    await model.publishQuote(quote, in: modelContext)
                    showResult = true
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(model.isWorking)
            .help("Copy a link the client can use to pay this quote after they sign")
            .alert("Pay link", isPresented: $showResult) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.message.isEmpty ? "Couldn’t create the pay link." : model.message)
            }
        }
    }
}

/// Header control. Sits beside Preview on the invoice and on the editor.
struct InvoicePayLinkButton: View {
    var invoice: Invoice

    @Environment(\.modelContext) private var modelContext
    @State private var model = PayLinkModel()
    @State private var showResult = false

    var body: some View {
        if invoice.canRecordPayment || !invoice.payToken.isEmpty {
            Button(invoice.payToken.isEmpty ? "Create pay link" : "Copy pay link", systemImage: "link") {
                if invoice.payToken.isEmpty {
                    Task {
                        await model.publish(invoice, in: modelContext)
                        showResult = true
                    }
                } else {
                    model.copyAgain(invoice)
                    showResult = true
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(model.isWorking)
            .help("Copy a link the client can use to pay this balance")
            .alert("Pay link", isPresented: $showResult) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.message.isEmpty ? "Couldn’t create the pay link." : model.message)
            }
        }
    }
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
