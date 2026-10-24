import SwiftUI

/// Checkboxes at the top leading of the open-balance card. Every customer starts included.
struct DashboardOpenCustomers: View {
    var customers: [OpenInvoiceCustomer]
    @Binding var excludedCustomers: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Customers")
                .font(.caption)
                .foregroundStyle(.secondary)
            if customers.count > 6 {
                ScrollView {
                    rows
                }
                .frame(maxHeight: 156)
                .scrollBounceBehavior(.basedOnSize)
            } else {
                rows
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Customers included in the open balance")
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(customers) { customer in
                Toggle(isOn: inclusion(for: customer.id)) {
                    HStack(spacing: 8) {
                        Text(customer.name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 8)
                        Text(customer.balance, format: .currency(code: "USD"))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .layoutPriority(1)
                    }
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .font(.subheadline)
                .accessibilityValue(StudioMoney.string(customer.balance))
                .accessibilityHint("Include in the open balance")
            }
        }
    }

    private func inclusion(for id: String) -> Binding<Bool> {
        Binding(
            get: { !excludedCustomers.contains(id) },
            set: { included in
                if included {
                    excludedCustomers.remove(id)
                } else {
                    excludedCustomers.insert(id)
                }
            }
        )
    }
}
