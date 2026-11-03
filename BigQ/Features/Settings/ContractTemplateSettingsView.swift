import SwiftData
import SwiftUI

struct ContractTemplateSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Contract> { $0.isTemplate }, sort: \Contract.title)
    private var templates: [Contract]
    @State private var selection: PersistentIdentifier?
    @State private var lockedSelection: PersistentIdentifier?
    @State private var saveFlash = false

    private var editing: Contract? {
        let id = selection ?? lockedSelection
        guard let id else { return nil }
        return templates.first { $0.persistentModelID == id }
    }

    var body: some View {
        HStack(spacing: 0) {
            templateList
                .frame(width: 240)
            Divider()
            if let editing {
                AgreementTemplateEditorPane(
                    contract: editing,
                    saveFlash: saveFlash,
                    onDelete: { delete(editing) },
                    onSave: { html in persist(editing, html: html) }
                )
                .id(editing.persistentModelID)
            } else {
                StudioEmptyState(
                    title: "No template selected",
                    message: "Build an agreement with fields for client, job, studio, and quote details.",
                    symbol: "signature"
                )
            }
        }
        .onAppear {
            if selection == nil {
                selection = templates.first?.persistentModelID
                lockedSelection = selection
            }
        }
        .onChange(of: selection) { _, new in
            if let new {
                lockedSelection = new
            } else if let lockedSelection, templates.contains(where: { $0.persistentModelID == lockedSelection }) {
                // List sometimes clears selection when SwiftData refreshes — put it back.
                selection = lockedSelection
            }
        }
        .onChange(of: templateIDs) { _, ids in
            if let locked = lockedSelection, ids.contains(locked) {
                if selection != locked { selection = locked }
                return
            }
            selection = ids.first
            lockedSelection = selection
        }
    }

    private var templateIDs: [PersistentIdentifier] {
        templates.map(\.persistentModelID)
    }

    private var templateList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Agreement Templates")
                    .font(.headline)
                Spacer()
                Button("New", systemImage: "plus", action: createTemplate)
                    .help("New agreement template")
            }
            .padding(16)
            List(templates, selection: $selection) { template in
                Text(template.displayTitle)
                    .tag(template.persistentModelID)
            }
            .listStyle(.sidebar)
        }
    }

    private func createTemplate() {
        let contract = Contract(
            title: "Untitled agreement",
            status: "template",
            html: starterBody,
            isTemplate: true
        )
        modelContext.insert(contract)
        try? modelContext.save()
        selection = contract.persistentModelID
        lockedSelection = selection
    }

    private func delete(_ contract: Contract) {
        modelContext.delete(contract)
        try? modelContext.save()
        selection = templates.first?.persistentModelID
        lockedSelection = selection
    }

    private func persist(_ contract: Contract, html: String) {
        contract.html = html
        try? modelContext.save()
        saveFlash = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            saveFlash = false
        }
    }

    private var starterBody: String {
        """
        <p>This agreement is between <span style="background-color:#b8e0f5;">[Studio Name]</span> and <span style="background-color:#b8e0f5;">[Client Name]</span>.</p>
        <p>Event date: <span style="background-color:#b8e0f5;">[Event Date]</span></p>
        <p>Job: <span style="background-color:#b8e0f5;">[Job Name]</span></p>
        <ol>
        <li><b>Agreement</b> — The studio agrees to provide photography services for the client.</li>
        <li><b>Services</b> — <span style="background-color:#b8e0f5;">[Quote Details]</span></li>
        <li><b>Payment</b> — Subtotal: <span style="background-color:#b8e0f5;">[Subtotal]</span>. Total due (incl. tax): <span style="background-color:#b8e0f5;">[Total Amount]</span>. Schedule: <span style="background-color:#b8e0f5;">[Terms]</span>.</li>
        <li><b>Cancellation</b> — Terms for ending this agreement.</li>
        </ol>
        """
    }
}
