import SwiftData
import SwiftUI

struct RecordPaymentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    var invoice: Invoice

    @State private var amount: Decimal
    @State private var paidAt = Date.now
    @State private var methods = PaymentMethodCatalog()
    @State private var methodKey = PaymentMethod.manual.rawValue
    @State private var methodTag = MethodMenuTag.method(PaymentMethod.manual.rawValue)
    @State private var showAddType = false
    @State private var newTypeName = ""
    @State private var duplicateMessage: String?
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
            Picker("Method", selection: $methodTag) {
                ForEach(methods.names, id: \.self) { key in
                    Text(PaymentMethod.displayTitle(for: key)).tag(MethodMenuTag.method(key))
                }
                Text("Other").tag(MethodMenuTag.other)
            }
            .pickerStyle(.menu)
            .onChange(of: methodTag) { _, tag in
                handleMethodTag(tag)
            }
            .alert("Add payment type", isPresented: $showAddType) {
                TextField("Payment type", text: $newTypeName)
                Button("Add", action: commitNewType)
                Button("Cancel", role: .cancel) { newTypeName = "" }
            }
            if let duplicateMessage {
                Text(duplicateMessage)
                    .foregroundStyle(.red)
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
        .studioActive()
    }

    private func handleMethodTag(_ tag: MethodMenuTag) {
        switch tag {
        case .other:
            showAddType = true
            let revert = MethodMenuTag.method(methodKey)
            Task { @MainActor in
                if methodTag == .other {
                    methodTag = revert
                }
            }
        case .method(let key):
            methodKey = key
            duplicateMessage = nil
        }
    }

    private func commitNewType() {
        let typed = newTypeName
        newTypeName = ""
        switch methods.add(typed) {
        case .added(let key):
            methodKey = key
            methodTag = .method(key)
            duplicateMessage = nil
        case .duplicate(let existing):
            duplicateMessage = "\(existing) is already a payment type."
        case .empty:
            break
        }
    }

    private func save() {
        let receipt = PaymentReceipt(paidAt: paidAt, amount: amount)
        receipt.methodRaw = methodKey
        receipt.invoice = invoice
        modelContext.insert(receipt)
        BooksTrail.notePayment(
            invoice,
            amount: amount,
            methodName: PaymentMethod.displayTitle(for: methodKey),
            in: modelContext
        )
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

private enum MethodMenuTag: Hashable {
    case method(String)
    case other
}
