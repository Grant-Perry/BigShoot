import SwiftData
import SwiftUI

struct ContactDetailView: View {
    @Environment(\.modelContext) private var modelContext
    var contact: Contact
    var onEdit: () -> Void
    var onOpenJob: (PersistentIdentifier) -> Void
    var onOpenInvoice: (PersistentIdentifier) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StudioDesign.Spacing.section) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(contact.displayName)
                        .font(StudioDesign.displayHero)
                    if !contact.companyName.isEmpty {
                        Text(contact.companyName)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                .textSelection(.enabled)

                VStack(alignment: .leading, spacing: 8) {
                    detailRow("Email", contact.email)
                    detailRow("Phone", contact.phone)
                    detailRow("Address", contact.address)
                    detailRow("Anniversary", StudioDay.string(contact.anniversary))
                }
                .padding(StudioDesign.Spacing.card)
                .paperCard()
                .textSelection(.enabled)

                linkedSection("Jobs", symbol: "camera") {
                    if contact.jobs.isEmpty {
                        Text("No jobs yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(contact.jobs.sorted { ($0.eventDate ?? .distantPast) > ($1.eventDate ?? .distantPast) }) { job in
                        Button {
                            onOpenJob(job.persistentModelID)
                        } label: {
                            HStack {
                                Text(job.displayName)
                                Spacer()
                                Text(StudioDay.string(job.eventDate))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                linkedSection("Invoices", symbol: "doc.text") {
                    if contact.invoices.isEmpty {
                        Text("No invoices yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(contact.invoices.sorted { $0.invoiceDate > $1.invoiceDate }) { invoice in
                        Button {
                            onOpenInvoice(invoice.persistentModelID)
                        } label: {
                            HStack {
                                Text(invoice.displayNumber)
                                StatusBadge(status: invoice.displayStatus)
                                Spacer()
                                Text(StudioMoney.string(invoice.balance))
                                    .monospacedDigit()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(StudioDesign.Spacing.workspace)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit", systemImage: "pencil", action: onEdit)
            }
            ToolbarItem {
                Button(contact.archived ? "Unarchive" : "Archive") {
                    contact.archived.toggle()
                    try? modelContext.save()
                }
            }
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .frame(width: 110, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(value.isEmpty || value == "—" ? "—" : value)
        }
    }

    private func linkedSection<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content()
        }
    }
}
