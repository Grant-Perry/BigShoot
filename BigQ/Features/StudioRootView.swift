import SwiftData
import SwiftUI

struct StudioRootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var section: StudioSection = .dashboard
    @State private var contactID: PersistentIdentifier?
    @State private var jobID: PersistentIdentifier?
    @State private var invoiceID: PersistentIdentifier?
    @State private var quoteID: PersistentIdentifier?
    @State private var showNewItemChooser = false
    @State private var pendingNewItem: NewStudioItem?
    @State private var showNewInvoice = false
    @State private var showNewQuote = false
    @State private var showNewJob = false
    @State private var showNewContact = false
    @State private var showNewCatalogItem = false
    @State private var exportError: String?
    @State private var importModel = ShootQImportModel()
    @Query(sort: \StudioBrand.name) private var studios: [StudioBrand]
    @Query(sort: \Contact.fullName) private var contacts: [Contact]
    @AppStorage(StudioBanner.key) private var bannerText = StudioBanner.fallback

    private var primaryStudioName: String {
        let primary = studios.first { $0.isPrimary && !$0.archived } ?? studios.first { !$0.archived }
        let name = primary?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Studio" : name
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 300)
            } detail: {
                detail
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            StudioAppFooterView()
        }
        .frame(minWidth: 1100, minHeight: 720)
        .sheet(isPresented: $showNewItemChooser, onDismiss: presentPendingNewItem) {
            NewItemChooserSheet { item in
                pendingNewItem = item
                showNewItemChooser = false
            }
        }
        .sheet(isPresented: $showNewInvoice) {
            NewInvoiceSheet(onOpenInvoice: openInvoice)
        }
        .sheet(isPresented: $showNewQuote) {
            NewQuoteSheet()
        }
        .sheet(isPresented: $showNewJob) {
            JobEditorSheet(contacts: contacts)
        }
        .sheet(isPresented: $showNewContact) {
            ContactEditorSheet(mode: .new)
        }
        .sheet(isPresented: $showNewCatalogItem) {
            CatalogItemSheet()
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
            do {
                try StudioBrandDirectory.prepare(in: modelContext)
            } catch {
                DebugPrint(mode: .error, "Could not prepare studios: \(error.localizedDescription)")
            }
            importModel.offerIfNeeded()
            await ShootQImporter(context: modelContext) { _, _ in }.importContractsIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bigQNewItem)) { _ in
            showNewItemChooser = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .bigShootNewInvoice)) { _ in
            showNewInvoice = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .bigQNewQuote)) { _ in
            showNewQuote = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .bigShootImport)) { _ in
            importModel.presentForImport()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bigShootExport)) { _ in
            exportBooks()
        }
    }

    private func presentPendingNewItem() {
        guard let item = pendingNewItem else { return }
        pendingNewItem = nil
        switch item {
        case .quote:
            section = .quotes
            showNewQuote = true
        case .invoice:
            section = .invoices
            showNewInvoice = true
        case .job:
            section = .jobs
            showNewJob = true
        case .contact:
            section = .contacts
            showNewContact = true
        case .catalogItem:
            section = .catalog
            showNewCatalogItem = true
        }
    }

    private var exportPresented: Binding<Bool> {
        Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })
    }

    private var sidebar: some View {
        List(selection: $section) {
            Section {
                ForEach(StudioSection.books) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                }
            }
            Section {
                Label(StudioSection.settings.title, systemImage: StudioSection.settings.symbol)
                    .tag(StudioSection.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("BigQ")
        .safeAreaInset(edge: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryStudioName)
                    .font(.system(size: 22, weight: .regular, design: .default))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                Text(StudioBanner.resolved(bannerText))
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
                onShowInvoices: { section = .invoices },
                onNewInvoice: { showNewInvoice = true }
            )
        case .contacts:
            ContactWorkspace(selection: $contactID, onOpenJob: openJob, onOpenInvoice: openInvoice)
        case .jobs:
            JobWorkspace(selection: $jobID, onOpenInvoice: openInvoice, onOpenQuote: openQuote)
        case .quotes:
            QuoteWorkspace(
                selection: $quoteID,
                showNewQuote: $showNewQuote,
                onOpenInvoice: openInvoice
            )
        case .invoices:
            InvoiceWorkspace(
                selection: $invoiceID,
                showNewInvoice: $showNewInvoice,
                onOpenInvoice: openInvoice
            )
        case .catalog:
            CatalogWorkspace()
        case .settings:
            SettingsWorkspace()
        }
    }

    private func openQuote(_ id: PersistentIdentifier) {
        quoteID = id
        section = .quotes
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
