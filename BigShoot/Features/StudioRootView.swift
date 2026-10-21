import SwiftData
import SwiftUI

struct StudioRootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var section: StudioSection = .dashboard
    @State private var contactID: PersistentIdentifier?
    @State private var jobID: PersistentIdentifier?
    @State private var invoiceID: PersistentIdentifier?
    @State private var showNewInvoice = false
    @State private var exportError: String?
    @State private var importModel = ShootQImportModel()

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 300)
        } detail: {
            detail
        }
        .frame(minWidth: 1100, minHeight: 720)
        .sheet(isPresented: $showNewInvoice) {
            NewInvoiceSheet()
        }
        .sheet(isPresented: $importModel.isPresentingOffer) {
            ImportOfferSheet(model: importModel)
        }
        .alert("Could not export", isPresented: exportPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .task {
            DebugConfig.configureFromLaunchArguments()
            importModel.offerIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bigShootNewInvoice)) { _ in
            showNewInvoice = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .bigShootImport)) { _ in
            importModel.presentForImport()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bigShootExport)) { _ in
            exportBooks()
        }
    }

    private var exportPresented: Binding<Bool> {
        Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })
    }

    private var sidebar: some View {
        List(StudioSection.allCases, selection: $section) { item in
            Label(item.title, systemImage: item.symbol)
                .tag(item)
        }
        .listStyle(.sidebar)
        .navigationTitle("BigShoot")
        .safeAreaInset(edge: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Grant & Deb")
                    .font(.system(size: 22, weight: .regular, design: .default))
                Text("Studio books")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch section {
        case .dashboard:
            DashboardView(
                onOpenInvoice: openInvoice,
                onShowInvoices: { section = .invoices }
            )
        case .contacts:
            ContactWorkspace(selection: $contactID, onOpenJob: openJob, onOpenInvoice: openInvoice)
        case .jobs:
            JobWorkspace(selection: $jobID, onOpenInvoice: openInvoice)
        case .invoices:
            InvoiceWorkspace(selection: $invoiceID, showNewInvoice: $showNewInvoice)
        case .catalog:
            CatalogWorkspace()
        }
    }

    private func openInvoice(_ id: PersistentIdentifier) {
        invoiceID = id
        section = .invoices
    }

    private func openJob(_ id: PersistentIdentifier) {
        jobID = id
        section = .jobs
    }

    private func exportBooks() {
        do {
            try StudioBooksExporter.export(context: modelContext)
        } catch {
            exportError = error.localizedDescription
        }
    }
}
