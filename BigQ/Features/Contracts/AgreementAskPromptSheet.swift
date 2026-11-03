import SwiftUI

/// Names a new ask field before it is dropped into the template.
struct AgreementAskPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onInsert: (String) -> Void
    @State private var prompt = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ask field")
                .font(StudioDesign.displayTitle)
            Text("This prompt appears when someone uses the template. It is not stored on a client or job.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Prompt", text: $prompt, prompt: Text("Bride’s Name"))
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Insert") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func save() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Dismiss first so the agreement editor stays mounted, then hand off the prompt.
        dismiss()
        onInsert(trimmed)
    }
}

/// Interview for every `[Ask: …]` still open — one question per Ask field.
struct AgreementAskAnswersSheet: View {
    @Environment(\.dismiss) private var dismiss
    var prompts: [String]
    var onComplete: ([String: String]) -> Void
    @State private var answers: [String: String] = [:]
    @FocusState private var focusedPrompt: String?

    private var allAnswered: Bool {
        prompts.allSatisfy { prompt in
            !(answers[prompt] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Fill agreement fields")
                .font(StudioDesign.displayTitle)
            Text(prompts.isEmpty
                ? "No Ask fields were found on this agreement."
                : "Answer each interview question. These values only live on this agreement.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if prompts.isEmpty {
                Text("Add gold Ask fields in the template, then try again.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(prompts.enumerated()), id: \.element) { index, prompt in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(index + 1). \(prompt)")
                                    .font(.headline)
                                TextField(prompt, text: binding(for: prompt))
                                    .textFieldStyle(.roundedBorder)
                                    .focused($focusedPrompt, equals: prompt)
                                    .onSubmit { focusNext(after: prompt) }
                            }
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button(prompts.isEmpty ? "Done" : "Apply") {
                    onComplete(answers)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!prompts.isEmpty && !allAnswered)
                .keyboardShortcut(.defaultAction)
                .help(allAnswered ? "Apply answers to the agreement" : "Answer every question first")
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear {
            for prompt in prompts where answers[prompt] == nil {
                answers[prompt] = ""
            }
            focusedPrompt = prompts.first
        }
    }

    private func binding(for prompt: String) -> Binding<String> {
        Binding(
            get: { answers[prompt] ?? "" },
            set: { answers[prompt] = $0 }
        )
    }

    private func focusNext(after prompt: String) {
        guard let index = prompts.firstIndex(of: prompt) else { return }
        let next = prompts.index(after: index)
        guard next < prompts.endIndex else { return }
        focusedPrompt = prompts[next]
    }
}
