import SwiftData
import SwiftUI

struct JobWorkspace: View {
    @Binding var selection: PersistentIdentifier?
    var onOpenInvoice: (PersistentIdentifier) -> Void

    @Query private var jobs: [Job]
    @Query(sort: \Contact.fullName) private var contacts: [Contact]
    @State private var showEditor = false

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
            JobListView(jobs: ordered, selection: $selection, onAdd: { showEditor = true })
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
    }
}

struct JobListView: View {
    let jobs: [Job]
    @Binding var selection: PersistentIdentifier?
    var onAdd: () -> Void
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
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .searchable(text: $search, prompt: "Job, type, or client")
        .navigationTitle("Jobs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Job", systemImage: "plus", action: onAdd)
            }
        }
        .overlay {
            if filtered.isEmpty {
                StudioEmptyState(title: "No jobs", message: "Import the ShootQ book, or add a shoot.", symbol: "camera")
            }
        }
    }
}
