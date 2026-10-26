import SwiftData
import SwiftUI

enum StudioBrandEditorMode: Identifiable {
    case new
    case existing(StudioBrand)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let studio): String(describing: studio.persistentModelID)
        }
    }

    var studio: StudioBrand? {
        if case .existing(let studio) = self { return studio }
        return nil
    }
}

struct StudioBrandEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    var mode: StudioBrandEditorMode

    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var address = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode.studio == nil ? "New studio" : "Edit studio")
                .font(StudioDesign.displayTitle)
            Form {
                TextField("Studio name", text: $name)
                TextField("Email", text: $email)
                TextField("Phone", text: $phone)
                LabeledContent("Address") {
                    TextEditor(text: $address)
                        .font(.body)
                        .frame(minHeight: 72)
                }
            }
            .formStyle(.grouped)
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed(name).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
        .studioActive()
        .onAppear(perform: load)
    }

    private func load() {
        guard let studio = mode.studio else { return }
        name = studio.name
        email = studio.email
        phone = studio.phone
        address = studio.address
    }

    private func save() {
        let studio = mode.studio ?? StudioBrand()
        if mode.studio == nil {
            modelContext.insert(studio)
        }
        studio.name = trimmed(name)
        studio.email = trimmed(email)
        studio.phone = trimmed(phone)
        studio.address = trimmed(address)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            DebugPrint(mode: .error, "Could not save the studio: \(error.localizedDescription)")
        }
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
