import SwiftData
import SwiftUI

struct ContactEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    var mode: ContactEditorMode

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var companyName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var hasAnniversary = false
    @State private var anniversary = Date.now

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode.contact == nil ? "New contact" : "Edit contact")
                .font(StudioDesign.displayTitle)
            Form {
                TextField("First name", text: $firstName)
                TextField("Last name", text: $lastName)
                TextField("Company", text: $companyName)
                TextField("Email", text: $email)
                TextField("Phone", text: $phone)
                TextField("Address", text: $address, axis: .vertical)
                Toggle("Anniversary", isOn: $hasAnniversary)
                if hasAnniversary {
                    DatePicker("Date", selection: $anniversary, displayedComponents: .date)
                }
            }
            .formStyle(.grouped)
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(displayName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear(perform: load)
    }

    private var displayName: String {
        let combined = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
        if !combined.isEmpty { return combined }
        return companyName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func load() {
        guard let contact = mode.contact else { return }
        firstName = contact.firstName
        lastName = contact.lastName
        companyName = contact.companyName
        email = contact.email
        phone = contact.phone
        address = contact.address
        if let date = contact.anniversary {
            hasAnniversary = true
            anniversary = date
        }
    }

    private func save() {
        let contact = mode.contact ?? Contact()
        if mode.contact == nil {
            modelContext.insert(contact)
        }
        contact.firstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        contact.lastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        contact.companyName = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        contact.fullName = displayName
        contact.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        contact.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        contact.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        contact.anniversary = hasAnniversary ? anniversary : nil
        try? modelContext.save()
        dismiss()
    }
}
