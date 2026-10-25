import SwiftData
import SwiftUI

enum StudioBrandScope: String, CaseIterable, Identifiable {
    case active
    case archived
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: "Active"
        case .archived: "Archived"
        case .all: "All"
        }
    }

    func includes(_ studio: StudioBrand) -> Bool {
        switch self {
        case .active: !studio.archived
        case .archived: studio.archived
        case .all: true
        }
    }
}

struct StudioBrandListView: View {
    let studios: [StudioBrand]
    @Binding var selection: PersistentIdentifier?
    var onAdd: () -> Void

    @State private var search = ""
    @State private var scope: StudioBrandScope = .active

    private var filtered: [StudioBrand] {
        studios
            .filter { studio in
                guard scope.includes(studio) else { return false }
                guard !search.isEmpty else { return true }
                return studio.displayName.localizedStandardContains(search)
                    || studio.email.localizedStandardContains(search)
                    || studio.phone.localizedStandardContains(search)
            }
            .sorted { lhs, rhs in
                if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary }
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }

    var body: some View {
        List(filtered, selection: $selection) { studio in
            VStack(alignment: .leading, spacing: 2) {
                Text(studio.displayName)
                HStack(spacing: 6) {
                    if studio.isPrimary {
                        Text("Primary")
                            .foregroundStyle(StudioDesign.gold)
                    }
                    if !studio.email.isEmpty {
                        Text(studio.email)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
            .tag(studio.persistentModelID)
            .padding(.vertical, 2)
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .searchable(text: $search, prompt: "Name or email")
        .toolbar {
            ToolbarItem {
                Picker("Show", selection: $scope) {
                    ForEach(StudioBrandScope.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Add Studio", systemImage: "plus", action: onAdd)
            }
        }
        .overlay {
            if filtered.isEmpty {
                StudioEmptyState(
                    title: "No studios",
                    message: scope == .archived ? "No studio is archived." : "Add the first studio.",
                    symbol: "building.2"
                )
            }
        }
    }
}
