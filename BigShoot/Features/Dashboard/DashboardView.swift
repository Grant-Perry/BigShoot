import SwiftData
import SwiftUI

struct DashboardView: View {
    @Query(sort: \Invoice.invoiceDate, order: .reverse) private var invoices: [Invoice]
    @Query(sort: \PaymentReceipt.paidAt, order: .reverse) private var receipts: [PaymentReceipt]
    @Query(sort: \StudioBrand.name) private var studios: [StudioBrand]
    @AppStorage(StudioBanner.key) private var bannerText = StudioBanner.fallback
    @State private var filter: DashboardLedgerFilter = .open
    @State private var window: CollectionWindow = .month

    var onOpenInvoice: (PersistentIdentifier) -> Void
    var onShowInvoices: () -> Void
    var onNewInvoice: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StudioDesign.Spacing.section) {
                DashboardHeader(
                    title: StudioBanner.resolved(bannerText),
                    subtitle: primaryStudio?.displayName ?? "Studio",
                    showsPrimaryNote: studios.count > 1
                )
                DashboardMetricStrip(
                    openBalance: StudioMoney.string(DashboardMath.openBalance(in: invoices)),
                    openCaption: openCaption,
                    overdueBalance: StudioMoney.string(DashboardMath.overdueBalance(in: invoices)),
                    overdueCaption: overdueCaption,
                    monthCollected: StudioMoney.string(DashboardMath.collectedThisMonth(in: receipts)),
                    yearCollected: StudioMoney.string(DashboardMath.collectedThisYear(in: receipts)),
                    yearCaption: yearCaption,
                    filter: $filter,
                    window: $window
                )
                HStack(alignment: .top, spacing: StudioDesign.Spacing.grid) {
                    DashboardInvoiceLedger(
                        invoices: invoices,
                        receipts: receipts,
                        buckets: report.buckets,
                        filter: $filter,
                        onOpenInvoice: onOpenInvoice,
                        onShowInvoices: onShowInvoices,
                        onNewInvoice: onNewInvoice
                    )
                    .frame(maxWidth: .infinity, alignment: .top)
                    VStack(spacing: StudioDesign.Spacing.grid) {
                        DashboardCollectionChart(window: $window, filter: $filter, report: report)
                        DashboardOpenBook(split: DashboardMath.openBook(in: invoices), filter: $filter)
                    }
                    .frame(width: 360)
                }
            }
            .padding(StudioDesign.Spacing.workspace)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(StudioSceneBackground())
        .navigationTitle("Dashboard")
    }

    private var primaryStudio: StudioBrand? {
        studios.first { $0.isPrimary && !$0.archived } ?? studios.first { !$0.archived }
    }

    private var report: CollectionReport {
        DashboardMath.collectionReport(receipts: receipts, window: window)
    }

    private var openCaption: String {
        let count = DashboardMath.openCount(in: invoices)
        return count == 1 ? "1 open invoice" : "\(count) open invoices"
    }

    private var overdueCaption: String {
        let count = DashboardMath.overdue(in: invoices).count
        if count == 0 { return "Nothing past due" }
        return count == 1 ? "1 invoice" : "\(count) invoices"
    }

    private var yearCaption: String {
        "Cash received · \(Date.now.formatted(.dateTime.year()))"
    }
}
