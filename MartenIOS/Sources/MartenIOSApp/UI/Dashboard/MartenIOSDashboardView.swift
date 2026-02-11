import CoreData
import MartenCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct MartenIOSDashboardView: View {
    @Bindable var container: MartenIOSAppContainer

    @FetchRequest(fetchRequest: dashboardPinboardFetchRequest())
    private var pinboards: FetchedResults<Pinboard>

    @State private var searchModel: DashboardSearchModel
    @State private var selectionModel = DashboardSelectionModel()

    @State private var isShowingPinboardManagement = false
    @State private var isShowingQuickAdd = false
    @State private var isShowingMoveSheet = false
    @State private var moveObjectIDs: [NSManagedObjectID] = []
    @State private var shareActivityItems: [Any] = []
    @State private var isShowingShareSheet = false
    @State private var pendingDeleteObjectIDs: [NSManagedObjectID] = []
    @State private var isShowingDeleteConfirmation = false
    @State private var activeDestination: ActiveDestination?

    init(container: MartenIOSAppContainer) {
        self.container = container
        _searchModel = State(
            initialValue: DashboardSearchModel(
                queryService: ClipItemQueryService(store: container.clipItemStore)
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if container.shouldShowIntegrationsOnboarding {
                integrationsOnboardingBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }

            DashboardSearchStackView(
                searchModel: searchModel,
                onOpenItem: { item in
                    handleItemTap(item)
                }
            )

            PinboardSwitcherView(
                pinboards: Array(pinboards),
                lockStateStore: container.lockStateStore,
                selectedPinboardID: Binding(
                    get: { container.selectedPinboardID },
                    set: { container.setSelectedPinboardID($0) }
                ),
                onManage: {
                    isShowingPinboardManagement = true
                },
                onDropPayload: { payload, pinboard in
                    handleDrop(payload: payload, to: pinboard)
                }
            )

            DashboardItemsSection(
                selectedPinboardID: container.selectedPinboardID,
                searchModel: searchModel,
                selectionModel: selectionModel,
                onTapItem: { item in
                    handleItemTap(item)
                },
                onCopyItem: { item in
                    copyItems([item.objectID])
                },
                onShareItem: { item in
                    shareItems([item.objectID])
                },
                onMoveItem: { item in
                    prepareMove([item.objectID])
                },
                onDeleteItem: { item in
                    prepareDelete([item.objectID])
                },
                onVisibleObjectIDsChanged: { visibleIDs in
                    if selectionModel.isSelectionMode {
                        selectionModel.selectedObjectIDs =
                            selectionModel.selectedObjectIDs.intersection(visibleIDs)
                    }
                }
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Marten")
        .toolbar {
            ToolbarItem(placement: selectionToolbarPlacement) {
                Button {
                    selectionModel.toggleSelectionMode()
                } label: {
                    Label(
                        selectionModel.isSelectionMode ? "Done" : "Select",
                        systemImage: selectionModel.isSelectionMode ? "checkmark.circle" : "checklist"
                    )
                }
                .accessibilityIdentifier("ios.dashboard.selectMode")
            }

            ToolbarItem(placement: quickAddToolbarPlacement) {
                MartenGlassProminentButton(action: {
                    isShowingQuickAdd = true
                }) {
                    Label("Quick Add", systemImage: "plus")
                }
                .accessibilityIdentifier("ios.dashboard.quickAdd")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selectionModel.isSelectionMode && selectionModel.hasSelection {
                DashboardSelectionActionBar(
                    selectedCount: selectionModel.selectedCount,
                    onCopy: {
                        copyItems(Array(selectionModel.selectedObjectIDs))
                    },
                    onMove: {
                        prepareMove(Array(selectionModel.selectedObjectIDs))
                    },
                    onShare: {
                        shareItems(Array(selectionModel.selectedObjectIDs))
                    },
                    onDelete: {
                        prepareDelete(Array(selectionModel.selectedObjectIDs))
                    },
                    onCancel: {
                        selectionModel.toggleSelectionMode()
                    }
                )
            }
        }
        .sheet(isPresented: $isShowingPinboardManagement) {
            PinboardManagementSheet(container: container)
        }
        .sheet(isPresented: $isShowingQuickAdd) {
            QuickAddMenuSheet(container: container)
        }
        .sheet(isPresented: $isShowingMoveSheet) {
            MoveToPinboardSheet(
                pinboards: moveTargetPinboards,
                lockStateStore: container.lockStateStore
            ) { pinboard in
                Task {
                    await container.moveItems(moveObjectIDs, toPinboardID: pinboard.objectID)
                    selectionModel.clearSelection()
                }
            }
        }
        .sheet(isPresented: $isShowingShareSheet) {
            ActivityView(activityItems: shareActivityItems)
        }
        .sheet(item: $activeDestination) { destination in
            switch destination {
            case .richText(let objectID):
                if let item = item(with: objectID) {
                    RichTextEditorSheet(item: item) { plainText, rtfData in
                        Task {
                            await container.updateRichTextItem(
                                objectID: objectID,
                                newText: plainText,
                                rtfData: rtfData
                            )
                        }
                    }
                }
            case .image(let objectID):
                if let item = item(with: objectID) {
                    ImageViewerSheet(item: item)
                }
            case .code(let objectID):
                if let item = item(with: objectID) {
                    CodeViewerSheet(item: item)
                }
            }
        }
        .alert(
            "Delete Items?",
            isPresented: $isShowingDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                let pendingIDs = pendingDeleteObjectIDs
                Task {
                    await container.deleteItems(pendingIDs)
                    selectionModel.clearSelection()
                }
                pendingDeleteObjectIDs = []
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteObjectIDs = []
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert(
            "Action Failed",
            isPresented: Binding(
                get: { container.lastOperationErrorMessage != nil },
                set: { _ in container.clearErrorMessage() }
            )
        ) {
            Button("OK") {
                container.clearErrorMessage()
            }
        } message: {
            Text(container.lastOperationErrorMessage ?? "Unknown error")
        }
        .task {
            await container.refreshPendingLinkPreviews()
            reconcilePinboardState()
            searchModel.selectedPinboardID = container.selectedPinboardID
        }
        .onChange(of: pinboardSignature) {
            reconcilePinboardState()
        }
        .onChange(of: container.selectedPinboardID) { _, newSelection in
            searchModel.selectedPinboardID = newSelection
            if let selectedID = newSelection,
                let pinboard = pinboards.first(where: { $0.id == selectedID })
            {
                searchModel.donateOpenPinboard(pinboard)
            }
        }
        .onDisappear {
            searchModel.stopVoiceDictation()
        }
    }

    private var pinboardSignature: String {
        pinboards
            .map(\.id.uuidString)
            .joined(separator: "|")
    }

    private var moveTargetPinboards: [Pinboard] {
        pinboards
            .filter { !$0.isSystemMarten }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var selectionToolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .automatic
        #endif
    }

    private var quickAddToolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .primaryAction
        #else
        .automatic
        #endif
    }

    private func reconcilePinboardState() {
        let validIDs = Set(pinboards.map(\.id))
        container.lockStateStore.reconcile(validPinboardIDs: validIDs)

        if let selectedPinboardID = container.selectedPinboardID,
            !validIDs.contains(selectedPinboardID)
        {
            container.setSelectedPinboardID(nil)
        }
    }

    private func handleItemTap(_ item: ClipItem) {
        if selectionModel.isSelectionMode {
            selectionModel.toggleSelection(for: item)
            return
        }

        searchModel.donateOpenItem(item)

        switch item.itemTypeValue {
        case .text, .richText:
            activeDestination = .richText(item.objectID)
        case .image:
            activeDestination = .image(item.objectID)
        case .code:
            activeDestination = .code(item.objectID)
        default:
            break
        }
    }

    private func prepareMove(_ objectIDs: [NSManagedObjectID]) {
        guard !objectIDs.isEmpty else { return }
        moveObjectIDs = objectIDs
        isShowingMoveSheet = true
    }

    private func prepareDelete(_ objectIDs: [NSManagedObjectID]) {
        guard !objectIDs.isEmpty else { return }
        pendingDeleteObjectIDs = objectIDs
        isShowingDeleteConfirmation = true
    }

    private func copyItems(_ objectIDs: [NSManagedObjectID]) {
        let items = resolveItems(from: objectIDs)
        let text = items
            .compactMap { item in
                item.plainTextContent?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? item.primaryText?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        guard !text.isEmpty else { return }
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif

        Task {
            try? await container.commandService.markItemsUsed(objectIDs: objectIDs)
        }
    }

    private func shareItems(_ objectIDs: [NSManagedObjectID]) {
        let items = resolveItems(from: objectIDs)
        guard !items.isEmpty else { return }

        var payloads: [Any] = []
        for item in items {
            payloads.append(contentsOf: bestEffortSharePayloads(for: item))
        }

        if payloads.isEmpty {
            let combinedText = items
                .compactMap { item in
                    normalizedText(for: item)
                }
                .joined(separator: "\n")

            if !combinedText.isEmpty {
                payloads = [combinedText]
            }
        }

        guard !payloads.isEmpty else { return }
        shareActivityItems = payloads
        isShowingShareSheet = true
    }

    private func resolveItems(from objectIDs: [NSManagedObjectID]) -> [ClipItem] {
        let context = container.persistenceController.viewContext
        return objectIDs.compactMap {
            try? context.existingObject(with: $0) as? ClipItem
        }
    }

    private func bestEffortSharePayloads(for item: ClipItem) -> [Any] {
        var payloads: [Any] = []

        if let shareURL = shareURL(for: item) {
            payloads.append(shareURL)
        }

        if item.itemTypeValue == .image,
            let imagePath = item.thumbnailPath?.trimmingCharacters(in: .whitespacesAndNewlines),
            !imagePath.isEmpty
        {
            let url = URL(fileURLWithPath: imagePath)
            if FileManager.default.fileExists(atPath: imagePath) {
                payloads.append(url)
            }

            #if canImport(UIKit)
            if let image = UIImage(contentsOfFile: imagePath) {
                payloads.append(image)
            }
            #endif
        }

        if let text = normalizedText(for: item) {
            payloads.append(text)
        }

        return payloads
    }

    private func normalizedText(for item: ClipItem) -> String? {
        let text =
            item.plainTextContent?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? item.primaryText?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private func shareURL(for item: ClipItem) -> URL? {
        if item.itemTypeValue == .file,
            let path = item.primaryText,
            !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            let fileURL = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL
            }
            return nil
        }

        if item.itemTypeValue == .url,
            let raw = item.primaryText?.trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        {
            if raw.localizedCaseInsensitiveContains("://") {
                return URL(string: raw)
            }
            return URL(string: "https://\(raw)")
        }

        return nil
    }

    private func item(with objectID: NSManagedObjectID) -> ClipItem? {
        let context = container.persistenceController.viewContext
        return try? context.existingObject(with: objectID) as? ClipItem
    }

    private var integrationsOnboardingBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "puzzlepiece.extension")
                .font(.headline)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text("Enable Integrations")
                    .font(.subheadline.weight(.semibold))
                Text("Set up Share Extension, Keyboard, Widgets, and Siri Shortcuts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button("Open") {
                container.openIntegrationsSettings()
            }
            .font(.caption.weight(.semibold))

            Button {
                container.dismissIntegrationsOnboarding()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss integrations onboarding")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor.opacity(0.12))
        )
    }

    private func handleDrop(payload: ItemDragPayload, to pinboard: Pinboard?) -> Bool {
        let coordinator = container.persistenceController.container.persistentStoreCoordinator
        let objectIDs = selectionModel.resolveObjectIDs(from: payload, coordinator: coordinator)
        guard !objectIDs.isEmpty else { return false }

        if let pinboard {
            Task {
                await container.moveItems(objectIDs, toPinboardID: pinboard.objectID)
                selectionModel.clearSelection()
            }
            return true
        }

        guard let selectedPinboardID = container.selectedPinboardID,
            let selectedPinboard = pinboards.first(where: { $0.id == selectedPinboardID })
        else {
            return false
        }

        Task {
            await container.removeItems(objectIDs, fromPinboardID: selectedPinboard.objectID)
            selectionModel.clearSelection()
        }
        return true
    }
}

private struct DashboardItemsSection: View {
    @FetchRequest private var items: FetchedResults<ClipItem>
    @Bindable var searchModel: DashboardSearchModel
    @Bindable var selectionModel: DashboardSelectionModel
    let onTapItem: (ClipItem) -> Void
    let onCopyItem: (ClipItem) -> Void
    let onShareItem: (ClipItem) -> Void
    let onMoveItem: (ClipItem) -> Void
    let onDeleteItem: (ClipItem) -> Void
    let onVisibleObjectIDsChanged: (Set<NSManagedObjectID>) -> Void

    init(
        selectedPinboardID: UUID?,
        searchModel: DashboardSearchModel,
        selectionModel: DashboardSelectionModel,
        onTapItem: @escaping (ClipItem) -> Void,
        onCopyItem: @escaping (ClipItem) -> Void,
        onShareItem: @escaping (ClipItem) -> Void,
        onMoveItem: @escaping (ClipItem) -> Void,
        onDeleteItem: @escaping (ClipItem) -> Void,
        onVisibleObjectIDsChanged: @escaping (Set<NSManagedObjectID>) -> Void
    ) {
        _items = FetchRequest(
            fetchRequest: dashboardItemsFetchRequest(selectedPinboardID: selectedPinboardID),
            animation: .default
        )
        self.searchModel = searchModel
        self.selectionModel = selectionModel
        self.onTapItem = onTapItem
        self.onCopyItem = onCopyItem
        self.onShareItem = onShareItem
        self.onMoveItem = onMoveItem
        self.onDeleteItem = onDeleteItem
        self.onVisibleObjectIDsChanged = onVisibleObjectIDsChanged
    }

    var body: some View {
        ItemCardGridView(
            items: displayedItems,
            selectionModel: selectionModel,
            onTapItem: onTapItem,
            onCopyItem: onCopyItem,
            onShareItem: onShareItem,
            onMoveItem: onMoveItem,
            onDeleteItem: onDeleteItem
        )
        .onAppear {
            searchModel.updateOptions(from: Array(items))
            onVisibleObjectIDsChanged(Set(displayedItems.map(\.objectID)))
        }
        .onChange(of: itemsSignature) {
            searchModel.updateOptions(from: Array(items))
            onVisibleObjectIDsChanged(Set(displayedItems.map(\.objectID)))
        }
        .onChange(of: searchModel.resultsSignature) {
            onVisibleObjectIDsChanged(Set(displayedItems.map(\.objectID)))
        }
    }

    private var displayedItems: [ClipItem] {
        searchModel.isSearchActive ? searchModel.results : Array(items)
    }

    private var itemsSignature: String {
        items.map { item in
            "\(item.objectID.uriRepresentation().absoluteString)-\(item.modifiedAt.timeIntervalSince1970)"
        }
        .joined(separator: "|")
    }
}

private func dashboardPinboardFetchRequest() -> NSFetchRequest<Pinboard> {
    let request = Pinboard.fetchRequest()
    request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
    request.returnsObjectsAsFaults = false
    return request
}

private func dashboardItemsFetchRequest(selectedPinboardID: UUID?) -> NSFetchRequest<ClipItem> {
    let request = ClipItem.fetchRequest()
    var predicates = [NSPredicate(format: "isTransient == NO")]

    if let selectedPinboardID {
        predicates.append(NSPredicate(format: "ANY pinboards.id == %@", selectedPinboardID as CVarArg))
    }

    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    request.sortDescriptors = [
        NSSortDescriptor(key: "displayOrder", ascending: false),
        NSSortDescriptor(key: "createdAt", ascending: false),
    ]
    request.returnsObjectsAsFaults = false
    request.relationshipKeyPathsForPrefetching = ["representations", "pinboards", "linkPreview"]

    return request
}

private enum ActiveDestination: Identifiable {
    case richText(NSManagedObjectID)
    case image(NSManagedObjectID)
    case code(NSManagedObjectID)

    var id: String {
        switch self {
        case .richText(let objectID):
            return "rich-\(objectID.uriRepresentation().absoluteString)"
        case .image(let objectID):
            return "image-\(objectID.uriRepresentation().absoluteString)"
        case .code(let objectID):
            return "code-\(objectID.uriRepresentation().absoluteString)"
        }
    }
}

private extension DashboardSearchModel {
    var resultsSignature: String {
        results.map(\.id.uuidString).joined(separator: "|")
    }
}
