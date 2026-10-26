import SwiftUI

/// Scope filter and sort, on one row when the card is wide enough.
struct DashboardLedgerControls: View {
    @Binding var scope: InvoiceScope?
    @Binding var sort: InvoiceLedgerSort
    @Binding var ascending: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 20) {
                scopePicker
                InvoiceLedgerSortBar(sort: $sort, ascending: $ascending)
            }
            VStack(alignment: .leading, spacing: 8) {
                scopePicker
                InvoiceLedgerSortBar(sort: $sort, ascending: $ascending)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scopePicker: some View {
        Picker("Which invoices", selection: $scope) {
            Text("Open").tag(Optional(InvoiceScope.open))
            Text("Overdue").tag(Optional(InvoiceScope.overdue))
            Text("All").tag(Optional(InvoiceScope.all))
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("Which invoices")
    }
}
