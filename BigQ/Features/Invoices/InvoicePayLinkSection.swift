import AppKit
import SwiftData
import SwiftUI

@MainActor
@Observable
final class PayLinkModel {
    var message = ""
    var isWorking = false
    /// Page copied on the last successful link. The result alert opens it.
    var page: URL?
    private(set) var copied = false

    func publish(_ invoice: Invoice, in context: ModelContext, replace: Bool = false) async {
        await run(invoice, in: context, create: true, replace: replace)
    }

    func refresh(_ invoice: Invoice, in context: ModelContext) async {
        guard !invoice.payToken.isEmpty || invoice.canRecordPayment else { return }
        await run(invoice, in: context, create: false)
    }

    private func run(_ invoice: Invoice, in context: ModelContext, create: Bool, replace: Bool = false) async {
        if create { page = nil }
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
            var keptExisting = false
            if create {
                let due = PayLinkAmount.forInvoice(invoice)
                let previous = invoice.payToken
                snapshot = try await api.publish(
                    invoiceId: invoiceId,
                    number: invoice.displayNumber,
                    amount: PayMoney.wire(due.amount),
                    amountKind: due.kind,
                    balance: PayMoney.wire(due.balance),
                    schedule: due.later,
                    billToName: invoice.clientName,
                    studioName: invoice.studio?.displayName ?? StudioBrand.defaultName,
                    replace: replace
                )
                keptExisting = replace && snapshot.token == previous
                invoice.payToken = snapshot.token
            } else {
                snapshot = try await api.status(invoiceId: invoiceId)
                invoice.payToken = snapshot.token
            }
            try context.save()
            let applied = try record(snapshot, on: invoice, in: context)
            if create {
                copy(snapshot.url)
                let due = PayLinkAmount.forInvoice(invoice)
                message = payLinkMessage(replaced: replace, kept: keptExisting, amount: due.amount)
                if snapshot.isPaid { message = "Paid online." }
                return
            }
            if snapshot.isPaid {
                message = "Paid online."
                return
            }
            if applied > 0 {
                message = "Recorded \(StudioMoney.string(applied))."
                return
            }
            if message.isEmpty {
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

    func publishQuote(_ quote: Quote, in context: ModelContext, replace: Bool = false, announce: Bool = true) async {
        page = nil
        let due = PayLinkAmount.forQuote(quote)
        guard due.amount > 0 else {
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
        let previous = quote.payToken
        let api = PayAPI(baseURL: PayAPI.liveBase, studioKey: studioKey)
        do {
            let snapshot = try await api.publish(
                invoiceId: quoteId,
                number: quote.displayNumber,
                amount: PayMoney.wire(due.amount),
                amountKind: due.kind,
                balance: PayMoney.wire(due.balance),
                schedule: due.later,
                billToName: quote.clientName,
                studioName: quote.studio?.displayName ?? StudioBrand.defaultName,
                replace: replace
            )
            quote.payToken = snapshot.token
            try context.save()
            if announce {
                copy(snapshot.url)
                message = payLinkMessage(
                    replaced: replace,
                    kept: replace && snapshot.token == previous,
                    amount: due.amount
                )
            } else {
                message = ""
            }
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
        page = URL(string: url)
    }

    func copyQuote(_ quote: Quote) {
        guard !quote.payToken.isEmpty else { return }
        copy(payURL(quote.payToken).absoluteString)
        message = "Pay link copied."
    }

    func copyAgain(_ invoice: Invoice) {
        guard !invoice.payToken.isEmpty else { return }
        copy(payURL(invoice.payToken).absoluteString)
        message = "Pay link copied."
    }
}

struct PayLinkResultAlert: ViewModifier {
    @Binding var isPresented: Bool
    var model: PayLinkModel
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content.alert("Pay link", isPresented: $isPresented) {
            if let page = model.page {
                Button("View on the Web") { openURL(page) }
                    .help("Open the pay page")
            }
            Button("OK", role: .cancel) {}
                .help("Dismiss")
        } message: {
            Text(model.message.isEmpty ? "Couldn’t create the pay link." : model.message)
        }
    }
}

extension View {
    func payLinkResultAlert(isPresented: Binding<Bool>, model: PayLinkModel) -> some View {
        modifier(PayLinkResultAlert(isPresented: isPresented, model: model))
    }

    fileprivate func commandHeld(_ held: Binding<Bool>) -> some View {
        modifier(CommandHeldModifier(held: held))
    }
}

private struct CommandHeldModifier: ViewModifier {
    @Binding var held: Bool
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear { start() }
            .onDisappear { stop() }
    }

    private func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let down = event.modifierFlags.contains(.command)
            MainActor.assumeIsolated { held = down }
            return event
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        held = false
    }
}

private func payLinkMessage(replaced: Bool, kept: Bool, amount: Decimal) -> String {
    if kept { return "A payment is already on this link, so it was kept." }
    let figure = StudioMoney.string(amount)
    if replaced { return "New pay link copied for \(figure)." }
    return "Pay link copied for \(figure)."
}

private func payURL(_ token: String) -> URL {
    PayAPI.liveBase.appendingPathComponent("pay").appendingPathComponent(token)
}

struct QuotePayLinkButton: View {
    var quote: Quote

    @Environment(\.modelContext) private var modelContext
    @State private var model = PayLinkModel()
    @State private var showResult = false
    @State private var commandHeld = false

    var body: some View {
        if quote.total > 0 && quote.status != .void {
            let hasLink = !quote.payToken.isEmpty
            Button(hasLink && !commandHeld ? "Copy pay link" : "Create pay link", systemImage: "link") {
                let replace = NSEvent.modifierFlags.contains(.command) && hasLink
                if !hasLink || replace {
                    Task {
                        await model.publishQuote(quote, in: modelContext, replace: replace)
                        showResult = true
                    }
                } else {
                    model.copyQuote(quote)
                    showResult = true
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(model.isWorking)
            .commandHeld($commandHeld)
            .help(hasLink
                ? "Copy the pay link. Hold ⌘ and click to create a new one and replace this link."
                : "Copy a link the client can use to pay this quote after they sign")
            .payLinkResultAlert(isPresented: $showResult, model: model)
        }
    }
}

/// Header control. Sits beside Preview on the invoice and on the editor.
struct InvoicePayLinkButton: View {
    var invoice: Invoice

    @Environment(\.modelContext) private var modelContext
    @State private var model = PayLinkModel()
    @State private var showResult = false
    @State private var commandHeld = false

    var body: some View {
        if invoice.canRecordPayment || !invoice.payToken.isEmpty {
            let hasLink = !invoice.payToken.isEmpty
            Button(hasLink && !commandHeld ? "Copy pay link" : "Create pay link", systemImage: "link") {
                let replace = NSEvent.modifierFlags.contains(.command) && hasLink
                if !hasLink || replace {
                    Task {
                        await model.publish(invoice, in: modelContext, replace: replace)
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
            .commandHeld($commandHeld)
            .help(hasLink
                ? "Copy the pay link. Hold ⌘ and click to create a new one and replace this link."
                : "Copy a link the client can use to pay this balance")
            .payLinkResultAlert(isPresented: $showResult, model: model)
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
                        .help(invoice.payToken.isEmpty ? "Create a link the client can pay" : "Refresh the pay link")
                    }
                    if !invoice.payToken.isEmpty {
                        Button("Copy link") { model.copyAgain(invoice) }
                            .buttonStyle(.bordered)
                            .disabled(model.isWorking)
                            .help("Copy the pay link")
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
