import SwiftData
import SwiftUI

struct BackupSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var model = BackupSettingsModel()

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: StudioDesign.Spacing.section) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Backup")
                        .font(StudioDesign.displayTitle)
                    Text("Save the studio to a folder you can restore on this Mac or another one.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                choiceCard(title: "What to save", choices: BackupScope.allCases, selection: model.scope) { item in
                    model.scope = item
                } title: { $0.title } detail: { $0.detail }

                VStack(alignment: .leading, spacing: 8) {
                    Button("Back Up") {
                        model.backup(in: modelContext)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy)
                    Text("Agreements and logos are saved beside the books. Backing up into an existing folder leaves unchanged agreement files where they are.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                choiceCard(title: "How to restore", choices: BackupRestoreMode.allCases, selection: model.restoreMode) { item in
                    model.restoreMode = item
                } title: { $0.title } detail: { $0.detail }

                Button("Restore") {
                    model.chooseRestore(in: modelContext)
                }
                .buttonStyle(.bordered)
                .disabled(model.isBusy)

                if let status = model.status {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(model.statusIsError ? StudioDesign.rose : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(status)
                }
            }
            .padding(StudioDesign.Spacing.workspace)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(StudioSceneBackground())
        .alert(model.confirmTitle, isPresented: $model.isConfirming) {
            Button(model.restoreMode.actionTitle, role: model.restoreMode == .replace ? .destructive : nil) {
                model.performRestore(in: modelContext)
            }
            Button("Cancel", role: .cancel) {
                model.cancelRestore()
            }
        } message: {
            Text(model.confirmMessage)
        }
    }

    private func choiceCard<Choice: Identifiable & Equatable>(
        title: String,
        choices: [Choice],
        selection: Choice,
        select: @escaping (Choice) -> Void,
        title choiceTitle: @escaping (Choice) -> String,
        detail: @escaping (Choice) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            ForEach(choices) { choice in
                Button {
                    select(choice)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(choiceTitle(choice))
                        Text(detail(choice))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(StudioDesign.Spacing.card)
                    .paperCard(cornerRadius: StudioDesign.Radius.row)
                    .studioActive(choice == selection)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(choice == selection ? .isSelected : [])
            }
        }
    }
}
