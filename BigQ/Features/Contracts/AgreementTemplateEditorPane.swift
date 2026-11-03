import SwiftData
import SwiftUI

/// Full ShootQ-style template canvas: title, format bar, rich body, variable sidebar.
struct AgreementTemplateEditorPane: View {
    @Bindable var contract: Contract
    var saveFlash: Bool
    var onDelete: () -> Void
    var onSave: (String) -> Void

    @State private var session: AgreementEditorSession
    @State private var showAskPrompt = false

    init(contract: Contract, saveFlash: Bool, onDelete: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        self.contract = contract
        self.saveFlash = saveFlash
        self.onDelete = onDelete
        self.onSave = onSave
        _session = State(initialValue: AgreementEditorSession(html: contract.html))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                TextField("Template title", text: $contract.title)
                    .font(StudioDesign.displayTitle)
                    .textFieldStyle(.plain)
                Spacer()
                if saveFlash {
                    Text("Saved")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(StudioDesign.paid)
                }
                Button("Delete", role: .destructive, action: onDelete)
                Button("Save") {
                    session.pullFromTextView()
                    onSave(session.html)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Text("Edit Contract Template")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    AgreementFormatBar()
                    Divider()
                    AgreementRichTextEditor(session: session)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Divider()
                AgreementVariableSidebar(
                    onInsert: { session.insertToken($0.token) },
                    onAskField: { showAskPrompt = true }
                )
            }
            .studioCard(cornerRadius: 14)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(StudioSceneBackground())
        .onChange(of: contract.persistentModelID) { _, _ in
            session = AgreementEditorSession(html: contract.html)
        }
        .sheet(isPresented: $showAskPrompt) {
            AgreementAskPromptSheet { prompt in
                // Dismiss first, then insert after the sheet is gone so the editor stays mounted.
                let token = AgreementAskField.token(prompt: prompt)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(50))
                    session.insertToken(token)
                }
            }
        }
    }
}
