import SwiftData
import SwiftUI

struct RecordPaymentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    var invoice: Invoice

    @State private var amount: Decimal
    @State private var paidAt = Date.now
    @State private var method: PaymentMethod = .manual
    @State private var errorMessage: String?

    init(invoice: Invoice) {
        self.invoice = invoice
        _amount = State(initialValue: max(invoice.balance, 0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Record payment")
                .font(StudioDesign.displayTitle)
            Text("\(invoice.displayNumber) · \(invoice.clientName)")
                .foregroundStyle(.secondary)
            Text("Balance \(StudioMoney.string(invoice.balance))")
                .font(StudioDesign.metric(22))
                .monospacedDigit()
            TextField("Amount", value: $amount, format: .number.precision(.fractionLength(2)))
            DatePicker("Paid", selection: $paidAt, displayedComponents: .date)
            Picker("Method", selection: $method) {
                ForEach(PaymentMethod.allCases, id: \.self) { item in
                    Text(item.title).tag(item)
                }
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Save Payment", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(amount <= 0)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func save() {
        let receipt = PaymentReceipt(paidAt: paidAt, amount: amount, method: method)
        receipt.invoice = invoice
        modelContext.insert(receipt)
        BooksTrail.notePayment(invoice, amount: amount, method: method, in: modelContext)
        invoice.amountPaid += amount
        invoice.balance = invoice.total - invoice.amountPaid
        if invoice.status == .draft {
            invoice.status = .pending
        }
        InvoiceMath.applyDerivedStatus(invoice, now: paidAt)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
