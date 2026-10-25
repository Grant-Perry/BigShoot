import SwiftData
import SwiftUI

struct StudioBrandDetailView: View {
    @Environment(\.modelContext) private var modelContext
    var studio: StudioBrand
    var studios: [StudioBrand]

    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StudioDesign.Spacing.section) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(studio.displayName)
                        .font(StudioDesign.displayHero)
                    if studio.isPrimary {
                        Text("Primary studio")
                            .font(.title3)
                            .foregroundStyle(StudioDesign.gold)
                    }
                }
                .textSelection(.enabled)

                Text(roleLine)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 12) {
                    field("Name", text: $name, prompt: "Studio name")
                    field("Email", text: $email, prompt: "grant@grantdeb.com")
                    field("Phone", text: $phone, prompt: "Add a phone number")
                    addressField
                    detailRow("Invoices", "\(studio.invoices.count)")
                }
                .padding(StudioDesign.Spacing.card)
                .paperCard()
                .onChange(of: name) { _, new in write(\.name, new) }
                .onChange(of: email) { _, new in write(\.email, new) }
                .onChange(of: phone) { _, new in write(\.phone, new) }
                .onChange(of: address) { _, new in write(\.address, new) }

                Text("Edits save as you type.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(StudioDesign.Spacing.workspace)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .task(id: studio.persistentModelID) {
            load()
        }
        .toolbar {
            if !studio.isPrimary {
                ToolbarItem {
                    Button("Make Primary", action: makePrimary)
                }
            }
            ToolbarItem {
                Button(studio.archived ? "Unarchive" : "Archive", action: toggleArchive)
                    .disabled(!studio.archived && !StudioBrandDirectory.canArchive(studio, among: studios))
            }
            if StudioBrandDirectory.canDelete(among: studios) {
                ToolbarItem {
                    Button("Delete", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .confirmationDialog(
            "Delete \(studio.displayName)?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Studio", role: .destructive, action: deleteStudio)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Invoices stay on the books and move to the remaining primary studio. This cannot be undone.")
        }
    }

    private var roleLine: String {
        if studio.isPrimary {
            "New invoices, reminders, and the sidebar use this studio. Other studios can live here too."
        } else {
            "Invoices already issued under this studio keep it. Make it primary to use it on new invoices."
        }
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .frame(width: 110, alignment: .leading)
                .foregroundStyle(.secondary)
            TextField(title, text: text, prompt: Text(prompt))
                .textFieldStyle(.roundedBorder)
        }
    }

    /// Return inserts a line break here. A text field would treat it as done.
    private var addressField: some View {
        HStack(alignment: .top) {
            Text("Address")
                .frame(width: 110, alignment: .leading)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            TextEditor(text: $address)
                .font(.body)
                .frame(minHeight: 72)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.18))
                }
                .overlay(alignment: .topLeading) {
                    if address.isEmpty {
                        Text("Street, city")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 9)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .frame(width: 110, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "—" : value)
        }
    }

    private func load() {
        name = studio.name
        email = studio.email
        phone = studio.phone
        address = studio.address
    }

    private func write(_ keyPath: ReferenceWritableKeyPath<StudioBrand, String>, _ value: String) {
        guard studio[keyPath: keyPath] != value else { return }
        studio[keyPath: keyPath] = value
        do {
            try modelContext.save()
        } catch {
            DebugPrint(mode: .error, "Could not save the studio: \(error.localizedDescription)")
        }
    }

    private func makePrimary() {
        do {
            try StudioBrandDirectory.makePrimary(studio, in: modelContext)
        } catch {
            DebugPrint(mode: .error, "Could not set the primary studio: \(error.localizedDescription)")
        }
    }

    private func toggleArchive() {
        do {
            try StudioBrandDirectory.setArchived(studio, archived: !studio.archived, in: modelContext)
        } catch {
            DebugPrint(mode: .error, "Could not archive the studio: \(error.localizedDescription)")
        }
    }

    private func deleteStudio() {
        do {
            try StudioBrandDirectory.delete(studio, in: modelContext)
        } catch {
            DebugPrint(mode: .error, "Could not delete the studio: \(error.localizedDescription)")
        }
    }
}
