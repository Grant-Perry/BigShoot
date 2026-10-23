import SwiftUI

struct DashboardMetricStrip: View {
    var openBalance: String
    var openCaption: String
    var overdueBalance: String
    var overdueCaption: String
    var monthCollected: String
    var yearCollected: String
    var yearCaption: String
    @Binding var filter: DashboardLedgerFilter
    @Binding var window: CollectionWindow

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
                emphasis: filter.collectionWindow == .month ? StudioDesign.gold : nil,
                hint: "Show invoices paid this month",
                action: showCash(.month)
            )
            DashboardMetricCard(
                title: "This year",
                value: yearCollected,
                caption: yearCaption,
                symbol: "chart.bar",
                emphasis: filter.collectionWindow == .year ? StudioDesign.gold : nil,
                hint: "Show invoices paid this year",
                action: showCash(.year)
            )
        }
    }

    private func showCash(_ window: CollectionWindow) -> () -> Void {
        {
            self.window = window
            filter = .cash(window)
        }
    }
}
