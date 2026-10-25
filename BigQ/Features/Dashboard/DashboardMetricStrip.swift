import SwiftUI

struct DashboardMetricStrip: View {
    var openBalance: String
    var openCaption: String
    var overdueBalance: String
    var overdueCaption: String
    var monthCollected: String
    var yearCollected: String
    var yearCaption: String
    var monthInvoiced: Decimal
    var yearInvoiced: Decimal
    @Binding var filter: DashboardLedgerFilter
    @Binding var window: CollectionWindow

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 200), spacing: StudioDesign.Spacing.grid)],
            spacing: StudioDesign.Spacing.grid
        ) {
            DashboardMetricCard(
                title: "Open balance",
                value: openBalance,
                caption: openCaption,
                symbol: "dollarsign.circle",
                emphasis: filter == .open ? StudioDesign.gold : nil,
                hint: "Show open invoices",
                action: { filter = .open }
            )
            DashboardMetricCard(
                title: "Overdue",
                value: overdueBalance,
                caption: overdueCaption,
                symbol: "clock.badge.exclamationmark",
                emphasis: filter == .overdue ? StudioDesign.rose : nil,
                hint: "Show overdue invoices",
                action: { filter = .overdue }
            )
            DashboardMetricCard(
                title: "This month",
                value: monthCollected,
                caption: "Cash received",
                symbol: "calendar",
                emphasis: emphasis(for: .month),
                hint: "Show invoices paid this month",
                action: showCash(.month),
                invoiced: monthInvoiced,
                invoicedHint: CollectionWindow.month.billedCaption,
                invoicedSelected: filter.billedWindow == .month,
                invoicedAction: showIssued(.month)
            )
            DashboardMetricCard(
                title: "This year",
                value: yearCollected,
                caption: yearCaption,
                symbol: "chart.bar",
                emphasis: emphasis(for: .year),
                hint: "Show invoices paid this year",
                action: showCash(.year),
                invoiced: yearInvoiced,
                invoicedHint: CollectionWindow.year.billedCaption,
                invoicedSelected: filter.billedWindow == .year,
                invoicedAction: showIssued(.year)
            )
        }
    }

    private func emphasis(for window: CollectionWindow) -> Color? {
        if filter.collectionWindow == window { return StudioDesign.gold }
        if filter.billedWindow == window { return colorScheme == .dark ? .gpBlue : .gpBlueLight }
        return nil
    }

    private func showCash(_ window: CollectionWindow) -> () -> Void {
        {
            self.window = window
            filter = .cash(window)
        }
    }

    private func showIssued(_ window: CollectionWindow) -> () -> Void {
        {
            self.window = window
            filter = .issued(window)
        }
    }
}
