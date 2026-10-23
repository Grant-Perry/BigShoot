import SwiftUI

/// Search field pinned at the top of a list column. macOS `.searchable` only lands in the window toolbar.
struct StudioColumnSearch: View {
    @Binding var text: String
    var prompt: String
    var findLabel: String
    var insetsHorizontally = true

    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField(prompt, text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                if !text.isEmpty {
                    Button("Clear Search", systemImage: "xmark.circle.fill") {
                        text = ""
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, insetsHorizontally ? 12 : 0)
            .padding(.vertical, insetsHorizontally ? 8 : 4)

            Divider()
        }
        .background {
            Button(findLabel) {
                focused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }
}
