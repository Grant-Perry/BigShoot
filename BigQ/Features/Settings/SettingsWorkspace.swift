import SwiftData
import SwiftUI

struct SettingsWorkspace: View {
    @State private var category: SettingsCategory? = .studios
    @State private var studioID: PersistentIdentifier?

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsCategory.allCases, selection: $category) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Label(item.title, systemImage: item.symbol)
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 28)
                }
                .tag(item)
                .padding(.vertical, 4)
            }
            .listStyle(.sidebar)
            .frame(width: 240)
            .navigationTitle("Settings")
            Divider()
            switch category {
            case .studios, nil:
                StudioBrandWorkspace(selection: $studioID)
            case .banner:
                BannerSettingsView()
            case .backup:
                BackupSettingsView()
            }
        }
    }
}
