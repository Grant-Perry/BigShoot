import SwiftData
import SwiftUI

struct StudioBrandWorkspace: View {
    @Binding var selection: PersistentIdentifier?
    @Query(sort: \StudioBrand.name) private var studios: [StudioBrand]
    @State private var editor: StudioBrandEditorMode?

    private var selected: StudioBrand? {
        studios.first { $0.persistentModelID == selection }
    }

    var body: some View {
        HStack(spacing: 0) {
            StudioBrandListView(studios: studios, selection: $selection, onAdd: { editor = .new })
                .frame(width: 320)
            Divider()
            Group {
                if let selected {
                    StudioBrandDetailView(studio: selected, studios: studios)
                } else {
                    StudioEmptyState(
                        title: "No studio selected",
                        message: "Choose a studio, or add another one under this roof.",
                        symbol: "building.2"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(StudioSceneBackground())
        }
        .sheet(item: $editor) { mode in
            StudioBrandEditorSheet(mode: mode)
        }
        .onAppear(perform: selectPrimaryIfNeeded)
        .onChange(of: studios.count) { _, _ in
            selectPrimaryIfNeeded()
        }
    }

    private func selectPrimaryIfNeeded() {
        guard selection == nil || selected == nil else { return }
        selection = studios.first { $0.isPrimary }?.persistentModelID ?? studios.first?.persistentModelID
    }
}
