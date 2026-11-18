import Foundation
import SwiftData
import Testing
@testable import BigQ

@MainActor
struct PayLinkTests {
    @Test func wireAmountUsesTwoDecimalsWithoutGrouping() {
        #expect(PayMoney.wire(Decimal(string: "1400")!) == "1400.00")
        #expect(PayMoney.wire(Decimal(string: "85.5")!) == "85.50")
        #expect(PayMoney.wire(Decimal(string: "10.236")!) == "10.24")
    }

    @Test func snapshotDecodesAPaidLink() throws {
        let json = """
        {"token":"abc","url":"https://bigq-pay.web.app/pay/abc","invoiceId":"inv","number":"12","amount":"80.00","billToName":"Ada","studioName":"Studio","status":"paid","transactionId":"txn","cardLabel":"Visa •••• 1111","paidAt":"2026-11-18T17:54:00.000Z","failureMessage":""}
        """.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(PayLinkSnapshot.self, from: json)
        #expect(snapshot.isPaid)
        #expect(snapshot.recordedPayments.first?.chargedAmount == Decimal(string: "80.00"))
        #expect(snapshot.paidDate != nil)
    }

    @Test func cardPaymentUpdatesTheBalanceOnce() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let invoice = Invoice(number: "12", status: .pending, total: 80, amountPaid: 0, balance: 80, billToName: "Ada")
        context.insert(invoice)
        let first = try PayLedger.apply(
            amount: 80,
            paidAt: .now,
            methodKey: PaymentMethod.card.rawValue,
            methodName: "Visa •••• 1111",
            transactionID: "txn-1",
            to: invoice,
            in: context
        )
        #expect(first.alreadyRecorded == false)
        #expect(invoice.balance == 0)
        #expect(invoice.amountPaid == 80)
        #expect(invoice.status == .paid)
        #expect(invoice.receipts.count == 1)
        #expect(invoice.receipts.first?.processorTransactionID == "txn-1")

        let second = try PayLedger.apply(
            amount: 80,
            paidAt: .now,
            methodKey: PaymentMethod.card.rawValue,
            methodName: "Visa •••• 1111",
            transactionID: "txn-1",
            to: invoice,
            in: context
        )
        #expect(second.alreadyRecorded)
        #expect(invoice.receipts.count == 1)
        #expect(invoice.amountPaid == 80)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: StudioSchemaV13.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
