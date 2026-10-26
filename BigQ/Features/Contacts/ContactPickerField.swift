import SwiftData
import SwiftUI

/// Client chooser. Results stay in a popover so the form around it keeps its height.
struct ContactPickerField: View {
    let contacts: [Contact]
    @Binding var selection: Contact?
    var label = "Client"

    @State private var isOpen = false

    private var title: String {
        selection?.displayName ?? "Choose a client"
    }

    var body: some View {
        LabeledContent(label) {
            Button {
                isOpen = true
            } label: {
                HStack(spacing: 8) {
                    Text(title)
                        .lineLimit(1)
                        .foregroundStyle(selection == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(label)
            .accessibilityValue(title)
        }
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            ContactPickerList(contacts: contacts, selection: $selection, isOpen: $isOpen)
        }
    }
}

private struct ContactPickerList: View {
    let contacts: [Contact]
    @Binding var selection: Contact?
    @Binding var isOpen: Bool

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var matches: [Contact] {
        let active = contacts
            .filter { !$0.archived }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return active }
        return active.filter {
            $0.displayName.localizedStandardContains(trimmed) || $0.email.localizedStandardContains(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search clients", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    if matches.isEmpty {
                        Text(query.isEmpty ? "No clients yet." : "No client matches that.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    } else {
                        ForEach(matches) { contact in
                            ContactPickerRow(
                                name: contact.displayName,
                                detail: contact.email.isEmpty ? nil : contact.email,
                                isSelected: contact.persistentModelID == selection?.persistentModelID
                            ) {
                                selection = contact
                                isOpen = false
                            }
                        }
                    }
                }
                .padding(4)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(10)
        .frame(width: 380)
        .frame(height: min(420, CGFloat(max(matches.count, 1)) * 40 + 56))
        .onAppear {
            Task { @MainActor in
                searchFocused = true
            }
        }
    }
}

private struct ContactPickerRow: View {
    let name: String
    var detail: String?
    var isSelected: Bool
    var action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark" : "person")
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(hovered ? Color.white.opacity(0.85) : Color.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(hovered ? Color.white : Color.primary)
            .background(hovered ? Color.accentColor : Color.clear, in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .onHover { hovered = $0 }
    }
}
