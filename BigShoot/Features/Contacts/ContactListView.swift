import SwiftData
import SwiftUI

enum ContactScope: String, CaseIterable, Identifiable {
    case active
    case archived
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: "Active"
        case .archived: "Archived"
        case .all: "All"
        }
    }

    func includes(_ contact: Contact) -> Bool {
        switch self {
        case .active: !contact.archived
        case .archived: contact.archived
        case .all: true
        }
    }
}

struct ContactWorkspace: View {
    @Binding var selection: PersistentIdentifier?
    var onOpenJob: (PersistentIdentifier) -> Void
    var onOpenInvoice: (PersistentIdentifier) -> Void

    @Query(sort: \Contact.fullName) private var contacts: [Contact]
    @State private var editor: ContactEditorMode?

    private var selected: Contact? {
        contacts.first { $0.persistentModelID == selection }
    }

    var body: some View {
        HStack(spacing: 0) {
            ContactListView(contacts: contacts, selection: $selection, onAdd: { editor = .new })
                .frame(width: 360)
            Divider()
            Group {
                if let selected {
                    ContactDetailView(
                        contact: selected,
                        onEdit: { editor = .existing(selected) },
                        onOpenJob: onOpenJob,
                        onOpenInvoice: onOpenInvoice
                    )
                } else {
                    StudioEmptyState(
                        title: "No contact selected",
                        message: "Search the studio book, or add someone new.",
                        symbol: "person.crop.rectangle"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(StudioSceneBackground())
        }
        .sheet(item: $editor) { mode in
            ContactEditorSheet(mode: mode)
        }
    }
}

enum ContactEditorMode: Identifiable {
    case new
    case existing(Contact)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let contact): String(describing: contact.persistentModelID)
        }
    }

    var contact: Contact? {
        if case .existing(let contact) = self { return contact }
        return nil
    }
}

struct ContactListView: View {
    let contacts: [Contact]
    @Binding var selection: PersistentIdentifier?
    var onAdd: () -> Void

    @State private var search = ""
    @State private var scope: ContactScope = .active

    private var filtered: [Contact] {
        contacts.filter { contact in
            guard scope.includes(contact) else { return false }
            guard !search.isEmpty else { return true }
            return contact.displayName.localizedStandardContains(search)
                || contact.email.localizedStandardContains(search)
                || contact.companyName.localizedStandardContains(search)
        }
    }

    var body: some View {
        List(filtered, selection: $selection) { contact in
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName)
                if !contact.email.isEmpty {
                    Text(contact.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tag(contact.persistentModelID)
            .padding(.vertical, 2)
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .searchable(text: $search, prompt: "Name or email")
        .navigationTitle("Contacts")
        .toolbar {
            ToolbarItem {
                Picker("Show", selection: $scope) {
                    ForEach(ContactScope.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Add Contact", systemImage: "plus", action: onAdd)
            }
        }
        .overlay {
            if filtered.isEmpty {
                StudioEmptyState(
                    title: "No contacts",
                    message: scope == .archived ? "No one is archived." : "Import ShootQ, or add the first client.",
                    symbol: "person.2"
                )
            }
        }
    }
}
