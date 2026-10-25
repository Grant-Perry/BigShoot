import SwiftData
import SwiftUI

struct JobWorkspace: View {
    @Binding var selection: PersistentIdentifier?
    var onOpenInvoice: (PersistentIdentifier) -> Void

    @Query private var jobs: [Job]
    @Query(sort: \Contact.fullName) private var contacts: [Contact]
    @State private var showEditor = false
    @State private var editingJob: Job?

    private var ordered: [Job] {
        jobs.sorted { lhs, rhs in
            switch (lhs.eventDate, rhs.eventDate) {
            case let (left?, right?): left > right
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): lhs.displayName < rhs.displayName
            }
        }
    }

    private var selected: Job? {
        jobs.first { $0.persistentModelID == selection }
    }

    var body: some View {
        HStack(spacing: 0) {
            JobListView(
                jobs: ordered,
                selection: $selection,
                onAdd: { showEditor = true },
                onEdit: { editingJob = $0 }
            )
                .frame(width: 360)
            Divider()
            Group {
                if let selected {
                    JobDetailView(job: selected, onOpenInvoice: onOpenInvoice)
                } else {
                    StudioEmptyState(
                        title: "No job selected",
                        message: "Weddings, portraits, and the rest of the book live here.",
                        symbol: "camera"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(StudioSceneBackground())
        }
        .sheet(isPresented: $showEditor) {
            JobEditorSheet(contacts: contacts)
        }
        .sheet(item: $editingJob) { job in
            JobEditorSheet(contacts: contacts, job: job)
        }
    }
}

struct JobListView: View {
    let jobs: [Job]
    @Binding var selection: PersistentIdentifier?
    var onAdd: () -> Void
    var onEdit: (Job) -> Void
    @State private var search = ""

    private var filtered: [Job] {
        guard !search.isEmpty else { return jobs }
        return jobs.filter {
            $0.displayName.localizedStandardContains(search)
                || $0.jobType.localizedStandardContains(search)
                || ($0.contact?.displayName.localizedStandardContains(search) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            StudioColumnSearch(text: $search, prompt: "Job, type, or client", findLabel: "Find Job")
            List(filtered, selection: $selection) { job in
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.displayName)
                        .lineLimit(2)
                    Text([StudioDay.string(job.eventDate), job.jobType].filter { $0 != "—" && !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(job.persistentModelID)
                .padding(.vertical, 2)
                .contextMenu {
                    Button("Edit", systemImage: "pencil") {
                        onEdit(job)
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .overlay {
                if filtered.isEmpty {
                    StudioEmptyState(
                        title: search.isEmpty ? "No jobs" : "No matches",
                        message: search.isEmpty
                            ? "Import the ShootQ book, or add a shoot."
                            : "Try a different job, type, or client.",
                        symbol: "camera"
                    )
                }
            }
        }
        .navigationTitle("Jobs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Job", systemImage: "plus", action: onAdd)
            }
        }
    }
}
