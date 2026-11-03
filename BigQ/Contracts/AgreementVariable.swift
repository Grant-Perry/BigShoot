import Foundation

/// Merge field that can be inserted into an agreement template as `[Label]`.
struct AgreementVariable: Identifiable, Hashable, Sendable {
    var id: String { token }
    /// Exact token written into the template, including brackets.
    var token: String
    /// Sidebar chip title. May clarify meaning without changing the token.
    var label: String

    init(_ label: String) {
        self.label = label
        self.token = "[\(label)]"
    }

    init(label: String, token: String) {
        self.label = label
        self.token = token
    }
}

struct AgreementVariableGroup: Identifiable, Hashable, Sendable {
    var id: String { title }
    var title: String
    var variables: [AgreementVariable]
}

enum AgreementVariableCatalog {
    /// Sidebar action — not a merge field. Insert flow asks for the prompt label.
    static let askFieldActionLabel = "Ask field…"

    static let groups: [AgreementVariableGroup] = [
        AgreementVariableGroup(title: "Client", variables: [
            .init("Client Name"),
            .init("Client First Name"),
            .init("Client Last Name"),
            .init("Client Email"),
            .init("Client Phone"),
            .init("Client Company"),
            .init("Client Full Address"),
        ]),
        AgreementVariableGroup(title: "Job", variables: [
            .init("Job Name"),
            .init("Job Type"),
            .init("Job Status"),
            .init("Event Date"),
            .init("Primary Contact Name"),
        ]),
        AgreementVariableGroup(title: "Studio", variables: [
            .init("Studio Name"),
            .init("Studio Email"),
            .init("Studio Phone"),
            .init("Studio Address"),
        ]),
        AgreementVariableGroup(title: "Quote", variables: [
            .init("Quote Number"),
            .init("Quote Date"),
            .init("Valid Until"),
            .init("Subtotal"),
            AgreementVariable(label: "Total Amount (incl. tax)", token: "[Total Amount]"),
            .init("Total Tax"),
            .init("Total Discount"),
            .init("Remaining Balance"),
            AgreementVariable(label: "Terms (payment schedule)", token: "[Terms]"),
            AgreementVariable(
                label: "Quote Details (packages & contents)",
                token: "[Quote Details]"
            ),
        ]),
        AgreementVariableGroup(title: "Agreement", variables: [
            .init("Date Signed"),
            .init("Agreement Created Date"),
        ]),
    ]

    static var all: [AgreementVariable] {
        groups.flatMap(\.variables)
    }

    static let tokenPattern = #"\[[^\[\]]+\]"#
}
