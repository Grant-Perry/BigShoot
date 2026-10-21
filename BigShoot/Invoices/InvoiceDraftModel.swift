import Foundation
import SwiftData

struct DraftLine: Identifiable {
    let id = UUID()
    var name: String
    var detail: String
    var quantity: Decimal
    var unitPrice: Decimal
    var catalogItem: CatalogItem?

    var lineTotal: Decimal {
        InvoiceMath.lineTotal(quantity: quantity, unitPrice: unitPrice)
    }
}

@MainActor
@Observable
final class InvoiceDraftModel {
    var contact: Contact?
    var job: Job?
    var invoiceDate = Date.now
    var dueDate = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
    var tax: Decimal = 0
    var note = ""
    var lines: [DraftLine] = []
    private var editingID: PersistentIdentifier?

    var subtotal: Decimal {
        lines.reduce(Decimal.zero) { $0 + $1.lineTotal }
    }

    var total: Decimal {
        InvoiceMath.total(subtotal: subtotal, tax: tax, discount: 0, shipping: 0)
    }

    var canSave: Bool {
        contact != nil && lines.contains { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var isEditing: Bool { editingID != nil }

    func load(_ invoice: Invoice) {
        editingID = invoice.persistentModelID
        contact = invoice.contact
        job = invoice.job
        invoiceDate = invoice.invoiceDate
        dueDate = invoice.dueDate ?? invoiceDate
        tax = invoice.tax
        note = invoice.note
        lines = invoice.sortedLines.map { line in
            DraftLine(
                name: line.name,
                detail: line.detail,
                quantity: line.quantity,
                unitPrice: line.unitPrice,
                catalogItem: line.catalogItem
            )
        }
    }

    func addCatalogItem(_ item: CatalogItem) {
        lines.append(DraftLine(
            name: item.name,
            detail: item.detail,
            quantity: 1,
            unitPrice: item.defaultPrice,
            catalogItem: item
        ))
    }

    func addBlankLine() {
        lines.append(DraftLine(name: "", detail: "", quantity: 1, unitPrice: 0, catalogItem: nil))
    }

    func save(in context: ModelContext, markSent: Bool) throws -> Invoice {
        let creating = editingID == nil
        let invoice = try preparedInvoice(in: context)
        let wasDraft = invoice.status == .draft
        invoice.contact = contact
        invoice.job = job
        invoice.invoiceDate = invoiceDate
        invoice.dueDate = dueDate
        invoice.tax = tax
        invoice.note = note
        invoice.billToName = contact?.displayName ?? invoice.billToName
        invoice.discount = 0
        invoice.shipping = 0
        replaceLines(on: invoice, in: context)
        if markSent {
            if invoice.number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let numbers = try context.fetch(FetchDescriptor<Invoice>()).map(\.number)
                invoice.number = InvoiceMath.nextNumber(among: numbers)
            }
            if invoice.status == .draft {
                invoice.status = .pending
            }
        }
        InvoiceMath.recalculate(invoice)
        if markSent && (creating || wasDraft) {
            BooksTrail.noteMarkedSent(invoice, in: context)
        } else if creating {
            BooksTrail.noteCreated(invoice, in: context)
        } else {
            BooksTrail.noteEdited(invoice, in: context)
        }
        try context.save()
        return invoice
    }

    private func preparedInvoice(in context: ModelContext) throws -> Invoice {
        if let editingID, let existing = context.model(for: editingID) as? Invoice {
            return existing
        }
        let invoice = Invoice(status: .draft, isImported: false)
        context.insert(invoice)
        return invoice
    }

    private func replaceLines(on invoice: Invoice, in context: ModelContext) {
        for line in invoice.lines {
            if let item = line.catalogItem {
                item.timesUsed = max(0, item.timesUsed - 1)
            }
            context.delete(line)
        }
        invoice.lines.removeAll()
        let named = lines.enumerated().filter {
            !$0.element.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        for (position, draft) in named {
            let line = InvoiceLine(
                name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                detail: draft.detail,
                quantity: draft.quantity,
                unitPrice: draft.unitPrice,
                position: position
            )
            line.invoice = invoice
            line.catalogItem = draft.catalogItem
            draft.catalogItem?.timesUsed += 1
            context.insert(line)
        }
    }
}
