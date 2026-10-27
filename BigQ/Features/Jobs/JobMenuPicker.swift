import AppKit
import SwiftData
import SwiftUI

struct JobMenuPicker: View {
    let jobs: [Job]
    let selection: Job?
    var openBalance: [PersistentIdentifier: String] = [:]
    /// When a client already has an open invoice, existing jobs lead and "No job" sits at the bottom.
    var placeEscapesLast: Bool = false
    var onAdd: () -> Void
    var onSelect: (Job?) -> Void
    var onEdit: (Job) -> Void

    @State private var isOpen = false
    @State private var copiedName = false
    @State private var copyToken = 0

    private var title: String {
        selection?.displayName ?? "No job"
    }

    /// The name shown in the picker. Empty until a job with a real name is selected.
    private var copyableName: String? {
        guard let name = selection?.name.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        return name
    }

    var body: some View {
        LabeledContent("Job:") {
            HStack(spacing: 6) {
                jobButton
                copyButton
            }
        }
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            JobMenuList(
                jobs: jobs,
                selectionID: selection?.persistentModelID,
                openBalance: openBalance,
                placeEscapesLast: placeEscapesLast,
                onAdd: {
                    isOpen = false
                    onAdd()
                },
                onSelect: { job in
                    isOpen = false
                    onSelect(job)
                },
                onEdit: { job in
                    isOpen = false
                    onEdit(job)
                }
            )
        }
    }

    private var jobButton: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Job:")
        .accessibilityValue(title)
        .contextMenu {
            Button("Copy Job Name", systemImage: "doc.on.doc") {
                copyJobName()
            }
            .disabled(copyableName == nil)
        }
    }

    private var copyButton: some View {
        Button(action: copyJobName) {
            Image(systemName: copiedName ? "checkmark" : "doc.on.doc")
                .font(.body)
                .frame(width: 16, height: 16)
                .foregroundStyle(copiedName ? StudioDesign.gold : Color.primary)
        }
        .buttonStyle(.bordered)
        .disabled(copyableName == nil)
        .help(copiedName ? "Copied" : "Copy job name")
        .accessibilityLabel("Copy job name")
    }

    private func copyJobName() {
        guard let copyableName else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(copyableName, forType: .string)
        copiedName = true
        copyToken += 1
        let token = copyToken
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard copyToken == token else { return }
            copiedName = false
        }
    }
}

private struct JobMenuList: View {
    let jobs: [Job]
    let selectionID: PersistentIdentifier?
    var openBalance: [PersistentIdentifier: String]
    var placeEscapesLast: Bool
    var onAdd: () -> Void
    var onSelect: (Job?) -> Void
    var onEdit: (Job) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                addJobRow
                Divider()
                    .padding(.vertical, 4)
                if placeEscapesLast {
                    jobRows
                    Divider()
                        .padding(.vertical, 4)
                    noJobRow
                } else {
                    noJobRow
                    jobRows
                }
            }
            .padding(6)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 380)
        .frame(height: min(520, CGFloat(jobs.count + 2) * rowStride + 28))
    }

    private var rowStride: CGFloat {
        openBalance.isEmpty ? 30 : 46
    }

    private var addJobRow: some View {
        JobMenuRow(title: "Add a job", systemImage: "plus", isSelected: false, action: onAdd)
    }

    private var noJobRow: some View {
        JobMenuRow(title: "No job", isSelected: selectionID == nil) {
            onSelect(nil)
        }
    }

    private var jobRows: some View {
        ForEach(jobs) { job in
            JobMenuRow(
                title: job.displayName,
                detail: openBalance[job.persistentModelID],
                isSelected: job.persistentModelID == selectionID
            ) {
                onSelect(job)
            }
            .contextMenu {
                Button("Edit", systemImage: "pencil") {
                    onEdit(job)
                }
            }
            .accessibilityAction(named: "Edit") {
                onEdit(job)
            }
        }
    }
}

private struct JobMenuRow: View {
    let title: String
    var detail: String?
    var systemImage: String?
    var isSelected: Bool
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                rowIcon
                    .frame(width: 16, height: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
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
        .onHover { hovered = $0 }
    }

    @ViewBuilder
    private var rowIcon: some View {
        if isSelected {
            Image(systemName: "checkmark")
        } else if let systemImage {
            Image(systemName: systemImage)
        } else {
            Color.clear
        }
    }
}
