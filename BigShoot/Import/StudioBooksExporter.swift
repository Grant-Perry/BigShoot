import AppKit
import Foundation
import SwiftData

enum StudioBooksExporter {
    static func export(context: ModelContext) throws {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Choose a folder for the BigShoot CSV books."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let accessing = folder.startAccessingSecurityScopedResource()
        defer {
            if accessing { folder.stopAccessingSecurityScopedResource() }
        }

        let contacts = try context.fetch(FetchDescriptor<Contact>())
        let jobs = try context.fetch(FetchDescriptor<Job>())
        let invoices = try context.fetch(FetchDescriptor<Invoice>())
        let lines = try context.fetch(FetchDescriptor<InvoiceLine>())
        let receipts = try context.fetch(FetchDescriptor<PaymentReceipt>())
        let schedule = try context.fetch(FetchDescriptor<PaymentScheduleEntry>())

        try write(folder, "contacts.csv", header: ["name", "email", "phone", "address", "anniversary", "archived"], rows: contacts.map { contact in
            [
                contact.displayName,
                contact.email,
                contact.phone,
                contact.address,
                StudioDay.string(contact.anniversary),
                contact.archived ? "yes" : "no",
            ]
        })
        try write(folder, "jobs.csv", header: ["name", "date", "type", "status", "contact"], rows: jobs.map { job in
            [job.displayName, StudioDay.string(job.eventDate), job.jobType, job.status, job.contact?.displayName ?? ""]
        })
        try write(folder, "invoices.csv", header: ["number", "client", "date", "due", "status", "total", "paid", "balance"], rows: invoices.map { invoice in
            [
                invoice.displayNumber,
                invoice.clientName,
                StudioDay.string(invoice.invoiceDate),
                StudioDay.string(invoice.dueDate),
                invoice.displayStatus.rawValue,
                "\(invoice.total)",
                "\(invoice.amountPaid)",
                "\(invoice.balance)",
            ]
        })
        try write(folder, "invoice-lines.csv", header: ["invoice", "name", "quantity", "price", "detail"], rows: lines.map { line in
            [line.invoice?.displayNumber ?? "", line.name, "\(line.quantity)", "\(line.unitPrice)", line.detail]
        })
        try write(folder, "payments.csv", header: ["invoice", "date", "amount", "method"], rows: receipts.map { receipt in
            [receipt.invoice?.displayNumber ?? "", StudioDay.string(receipt.paidAt), "\(receipt.amount)", receipt.method.rawValue]
        })
        try write(folder, "schedule.csv", header: ["invoice", "due", "amount", "paid", "balance", "status"], rows: schedule.map { entry in
            [entry.invoice?.displayNumber ?? "", StudioDay.string(entry.due), "\(entry.amount)", "\(entry.amountPaid)", "\(entry.balance)", entry.status]
        })
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    private static func write(_ folder: URL, _ name: String, header: [String], rows: [[String]]) throws {
        var lines = [header.map(field).joined(separator: ",")]
        lines.append(contentsOf: rows.map { $0.map(field).joined(separator: ",") })
        let url = folder.appendingPathComponent(name)
        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func field(_ value: String) -> String {
        let dash = value == "—" ? "" : value
        if dash.contains(",") || dash.contains("\"") || dash.contains("\n") {
            return "\"" + dash.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return dash
    }
}
