import SwiftData
import SwiftUI

struct ContractTemplateSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Contract> { $0.isTemplate }, sort: \Contract.title)
    private var templates: [Contract]
    @State private var editing: Contract?
    @State private var showNew = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("Agreement Templates")
                        .font(.headline)
                    Spacer()
                    Button("New", systemImage: "plus") { showNew = true }
                }
                .padding(16)
                List(templates, selection: Binding(
                    get: { editing?.persistentModelID },
                    set: { id in editing = templates.first { $0.persistentModelID == id } }
                )) { template in
                    Text(template.displayTitle)
                        .tag(template.persistentModelID)
                }
                .listStyle(.sidebar)
            }
            .frame(width: 260)
            Divider()
            if let editing {
                ContractTemplateEditor(contract: editing, onDelete: {
                    modelContext.delete(editing)
                    try? modelContext.save()
                    self.editing = nil
                })
            } else {
                StudioEmptyState(
                    title: "No template selected",
                    message: "Write reusable agreements to attach when you build a quote.",
                    symbol: "signature"
                )
            }
        }
        .sheet(isPresented: $showNew) {
            NewContractTemplateSheet { created in
                editing = created
            }
        }
    }
}

private struct NewContractTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    var onCreated: (Contract) -> Void
    @State private var title = ""
    @State private var html = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New agreement template")
                .font(StudioDesign.displayTitle)
            TextField("Title", text: $title)
            TextEditor(text: $html)
                .font(.body)
                .frame(minHeight: 220)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private func save() {
        let contract = Contract(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            status: "template",
            html: html,
            isTemplate: true
        )
        modelContext.insert(contract)
        try? modelContext.save()
        onCreated(contract)
        dismiss()
    }
}

private struct ContractTemplateEditor: View {
    @Bindable var contract: Contract
    var onDelete: () -> Void
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Title", text: $contract.title)
                .font(StudioDesign.displayTitle)
            TextEditor(text: $contract.html)
                .font(.body)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Button("Delete Template", role: .destructive, action: onDelete)
                Spacer()
                Button("Save") {
                    try? modelContext.save()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }
}
