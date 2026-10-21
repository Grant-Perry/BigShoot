import SwiftData
import SwiftUI

struct DashboardView: View {
    @Query private var invoices: [Invoice]
    @Query private var receipts: [PaymentReceipt]
    @Query private var contacts: [Contact]

    var onOpenInvoice: (PersistentIdentifier) -> Void
    var onShowInvoices: () -> Void

    private var overdue: [Invoice] { DashboardMath.overdue(in: invoices) }
    private var anniversaries: [AnniversaryItem] { DashboardMath.upcomingAnniversaries(in: contacts) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StudioDesign.Spacing.section) {
                header
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: StudioDesign.Spacing.grid)],
                    spacing: StudioDesign.Spacing.grid
                ) {
                    metric("Open balance", StudioMoney.string(DashboardMath.openBalance(in: invoices)), "dollarsign.circle")
                    metric("Overdue", "\(overdue.count)", "clock.badge.exclamationmark")
                    metric("Collected this month", StudioMoney.string(DashboardMath.collectedThisMonth(in: receipts)), "tray.full")
                }
                HStack(alignment: .top, spacing: StudioDesign.Spacing.grid) {
                    overdueCard
                    anniversaryCard
                }
            }
            .padding(StudioDesign.Spacing.workspace)
        }
        .background(StudioSceneBackground())
        .navigationTitle("Dashboard")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Studio books")
                .font(StudioDesign.displayHero)
            Text("Grant & Deb Photography")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    private func metric(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(StudioDesign.metric(32))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(StudioDesign.Spacing.card)
        .studioCard()
    }

    private var overdueCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overdue")
                .font(StudioDesign.displayTitle)
            if overdue.isEmpty {
                Text("Nothing is past due.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(overdue.prefix(8)) { invoice in
                    Button {
                        onOpenInvoice(invoice.persistentModelID)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(invoice.clientName)
                                Text(invoice.displayNumber)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(StudioMoney.string(invoice.balance))
                                .font(StudioDesign.metric(16))
                                .monospacedDigit()
                        }
                    }
                    .buttonStyle(.plain)
                }
                if overdue.count > 8 {
                    Button("See all invoices", action: onShowInvoices)
                        .buttonStyle(.borderless)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(StudioDesign.Spacing.card)
        .studioCard()
    }

    private var anniversaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Anniversaries")
                .font(StudioDesign.displayTitle)
            if anniversaries.isEmpty {
                Text("No anniversaries on the books yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(anniversaries) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.contact.displayName)
                            Text(item.years == 1 ? "1 year" : "\(item.years) years")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(StudioDay.string(item.nextDate))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(StudioDesign.Spacing.card)
        .studioCard()
    }
}
