import CoreData
import MartenCore
import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
    import UIKit
#endif

struct MartenIOSDashboardView: View {
    @Bindable var container: MartenIOSAppContainer

    @FetchRequest(fetchRequest: dashboardPinboardFetchRequest())
    private var pinboards: FetchedResults<Pinboard>

    @FetchRequest(fetchRequest: searchAllItemsFetchRequest())
    private var allItems: FetchedResults<ClipItem>

    @State private var selectionModel = DashboardSelectionModel()
    @State private var searchModel: DashboardSearchModel?
    @State private var toastController = ToastController()

    @State private var searchFocusRequest = false

    @State private var isShowingPinboardManagement = false
    @State private var isShowingPinboardCreation = false
    @State private var isShowingPinboardPicker = false
    @State private var isShowingQuickAdd = false
    @State private var isShowingMoveSheet = false
    @State private var isShowingFilters = false
    @State private var moveObjectIDs: [NSManagedObjectID] = []
    @State private var shareActivityItems: [Any] = []
    @State private var isShowingShareSheet = false
    @State private var pendingDeleteObjectIDs: [NSManagedObjectID] = []
    @State private var isShowingDeleteConfirmation = false
    @State private var activeDestination: ActiveDestination?
    @State private var navigateToSettings = false
    @State private var pinboardEditorContext: PinboardEditorContext?
    @State private var pinboardShareContext: PinboardShareContext?
    @State private var pendingDeletePinboard: Pinboard?

    @ScaledMetric(relativeTo: .headline) private var actionButtonSize: CGFloat = 44

    var body: some View {
        ZStack(alignment: .top) {
            // Content area — fills entire screen, scrolls behind top/bottom bars
            Group {
                if isSelectedPinboardAwaitingUnlock {
                    selectedPinboardLockedContent
                } else if let searchModel, searchModel.isSearchActive {
                    searchResultsContent(searchModel: searchModel)
                } else {
                    DashboardItemsSection(
                        selectedPinboardID: container.selectedPinboardID,
                        isItemVisible: { item in
                            isItemVisible(item, selectedPinboardID: container.selectedPinboardID)
                        },
                        selectionModel: selectionModel,
                        onTapItem: { item in
                            handleItemTap(item)
                        },
                        onCopyItem: { item in
                            copyItems([item.objectID])
                        },
                        onCopyPlainTextItem: { item in
                            copyItemsPlainText([item.objectID])
                        },
                        onPreviewItem: { item in
                            handleItemPreview(item)
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
                        onReorderItems: { objectIDs in
                            reorderItems(objectIDs)
                        },
                        onVisibleObjectIDsChanged: { visibleIDs in
                            if selectionModel.isSelectionMode {
                                selectionModel.selectedObjectIDs =
                                    selectionModel.selectedObjectIDs.intersection(visibleIDs)
                            }
                        }
                    )
                    .id(dashboardItemsSectionID)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Top gradient fade at screen edge (behind controls, in front of cards)
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(
                            color: Color(platformColor: .platformSystemBackground).opacity(1.0),
                            location: 0.0),
                        .init(
                            color: Color(platformColor: .platformSystemBackground).opacity(0.0),
                            location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 100)
                .allowsHitTesting(false)

                Spacer()
            }
            .ignoresSafeArea()

            // Bottom gradient fade at screen edge (behind controls, in front of cards)
            VStack(spacing: 0) {
                Spacer()

                LinearGradient(
                    stops: [
                        .init(
                            color: Color(platformColor: .platformSystemBackground).opacity(0.0),
                            location: 0.0),
                        .init(
                            color: Color(platformColor: .platformSystemBackground).opacity(1.0),
                            location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()

            // Floating top bar
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                if container.shouldShowIntegrationsOnboarding {
                    integrationsOnboardingBanner
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(MartenAnimation.fadeScale)
                }

                if let searchModel, searchModel.hasActiveFilters {
                    activeFiltersChips(searchModel: searchModel)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }
            }

            // Floating bottom bar
            VStack {
                Spacer()
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
                            withAnimation(MartenAnimation.smooth) {
                                selectionModel.toggleSelectionMode()
                            }
                        }
                    )
                } else {
                    bottomBar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
        }
        #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
        #endif
        .toast(controller: toastController)
        .navigationDestination(isPresented: $navigateToSettings) {
            MartenIOSSettingsView(container: container)
        }
        .sheet(isPresented: $isShowingPinboardPicker) {
            PinboardPickerSheet(
                container: container,
                pinboards: Array(displayPinboards),
                lockStateStore: container.lockStateStore,
                selectedPinboardID: container.selectedPinboardID,
                onSelect: { pinboardID in
                    withAnimation(MartenAnimation.quick) {
                        container.setSelectedPinboardID(pinboardID)
                    }
                },
                onEdit: { pinboard in
                    isShowingPinboardPicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        pinboardEditorContext = PinboardEditorContext(
                            objectIDURI: pinboard.objectID.uriRepresentation().absoluteString,
                            name: pinboard.name,
                            colorHex: pinboard.colorHex,
                            iconName: pinboard.iconName
                        )
                    }
                },
                onShare: { pinboard in
                    isShowingPinboardPicker = false
                    if container.sharingRepository != nil {
                        let metadata = pinboard.shareMetadata
                        let initialShareURL = metadata?.shareURL.flatMap(URL.init(string:))
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            pinboardShareContext = PinboardShareContext(
                                pinboardID: pinboard.objectID,
                                initialAccessControl: metadata?.accessControl ?? .onlyInvited,
                                initialPermission: metadata?.defaultPermission ?? .canMakeChanges,
                                initialShareURL: initialShareURL
                            )
                        }
                    }
                },
                onDelete: { pinboard in
                    isShowingPinboardPicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        pendingDeletePinboard = pinboard
                    }
                },
                onReorder: { orderedIDs in
                    try? container.clipItemStore.reorderPinboards(orderedIDs: orderedIDs)
                },
                onCreate: {
                    isShowingPinboardCreation = true
                }
            )
        }
        .sheet(isPresented: $isShowingPinboardManagement) {
            PinboardManagementSheet(container: container)
        }
        .sheet(isPresented: $isShowingPinboardCreation) {
            PinboardEditorSheet(mode: .create) { name, colorHex, iconName in
                Task {
                    await container.createPinboard(
                        name: name, colorHex: colorHex, iconName: iconName)
                }
            }
        }
        .sheet(isPresented: $isShowingQuickAdd) {
            QuickAddMenuSheet(container: container)
        }
        .sheet(isPresented: $isShowingFilters) {
            if let searchModel {
                SearchFiltersSheet(searchModel: searchModel)
            }
        }
        .sheet(isPresented: $isShowingMoveSheet) {
            MoveToPinboardSheet(
                pinboards: moveTargetPinboards,
                lockStateStore: container.lockStateStore
            ) { destination in
                Task {
                    switch destination {
                    case .all:
                        await container.moveItemsToAll(moveObjectIDs)
                    case .pinboard(let pinboard):
                        await container.moveItems(moveObjectIDs, toPinboardID: pinboard.objectID)
                    }
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
                    RichTextEditorSheet(
                        item: item,
                        appleIntelligence: container.appleIntelligence
                    ) { plainText, rtfData in
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
            case .url(let objectID):
                if let item = item(with: objectID) {
                    URLViewerSheet(item: item)
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
        .sheet(item: $pinboardEditorContext) { context in
            PinboardEditorSheet(
                mode: .edit,
                initialName: context.name,
                initialColorHex: context.colorHex,
                initialIconName: context.iconName
            ) { updatedName, updatedColorHex, updatedIconName in
                guard let url = URL(string: context.objectIDURI),
                    let objectID = container.persistenceController.container
                        .persistentStoreCoordinator
                        .managedObjectID(forURIRepresentation: url)
                else { return }
                Task {
                    await container.updatePinboard(
                        objectID: objectID,
                        name: updatedName,
                        colorHex: updatedColorHex,
                        iconName: updatedIconName
                    )
                }
            }
        }
        .sheet(item: $pinboardShareContext) { context in
            if let sharingRepository = container.sharingRepository {
                ShareSettingsSheet(
                    pinboardID: context.pinboardID,
                    sharingRepository: sharingRepository,
                    initialAccessControl: context.initialAccessControl,
                    initialPermission: context.initialPermission,
                    initialShareURL: context.initialShareURL
                )
            }
        }
        .alert(
            "Delete Pinboard?",
            isPresented: Binding(
                get: { pendingDeletePinboard != nil },
                set: { if !$0 { pendingDeletePinboard = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                guard let pinboard = pendingDeletePinboard else { return }
                Task {
                    await container.deletePinboard(pinboard)
                }
                pendingDeletePinboard = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeletePinboard = nil
            }
        } message: {
            Text("All items in this pinboard will be removed. This cannot be undone.")
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
            let model = DashboardSearchModel(
                queryService: ClipItemQueryService(store: container.clipItemStore)
            )
            searchModel = model
            await container.refreshPendingLinkPreviews()
            reconcilePinboardState()
            model.updateOptions(from: visibleAllItemsForSearchOptions)
        }
        .onChange(of: pinboardSignature) {
            reconcilePinboardState()
        }
        .onChange(of: allItemsSignature) {
            searchModel?.updateOptions(from: visibleAllItemsForSearchOptions)
        }
        .onAppear {
            if let action = container.pendingWidgetAction {
                Task { @MainActor in
                    await performWidgetAction(action)
                }
            }
        }
        .onChange(of: container.pendingWidgetAction) { _, newValue in
            guard let action = newValue else { return }
            Task { @MainActor in
                await performWidgetAction(action)
            }
        }

    }

    private func performWidgetAction(_ action: MartenIOSAppContainer.WidgetAction) async {
        container.pendingWidgetAction = nil

        switch action {
        case .search:
            searchFocusRequest = true
        case .paste:
            await container.createItemFromClipboard()
            if container.lastOperationErrorMessage == nil {
                toastController.show("Saved from clipboard", systemImage: "doc.on.clipboard")
            }
        case .create:
            isShowingQuickAdd = true
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            if selectionModel.isSelectionMode {
                // Selection Count Indicator
                MartenGlassSurface(cornerRadius: 100, padding: 0, isInteractive: false) {
                    Text("\(selectionModel.selectedCount) Selected")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(minHeight: 24)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
                .transition(MartenAnimation.fadeScale)

                Spacer()
            } else {
                // Pinboard selector
                swipablePinboardSelector
                    .transition(MartenAnimation.fadeScale)

                Spacer()

                // Pinboard options (only when a specific pinboard is selected)
                if let pinboard = selectedPinboard, !pinboard.isSystemMarten {
                    pinboardOptionsMenu(for: pinboard)
                }
            }

            // Selection mode toggle — text label
            Button {
                withAnimation(MartenAnimation.smooth) {
                    selectionModel.toggleSelectionMode()
                }
            } label: {
                Text(selectionModel.isSelectionMode ? "Done" : "Select")
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: 24)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .glassChipBackground(isHighlighted: selectionModel.isSelectionMode)
            .accessibilityLabel(selectionModel.isSelectionMode ? "Done" : "Select")
            .accessibilityIdentifier("ios.dashboard.selectMode")

            // Settings button
            if !selectionModel.isSelectionMode {
                Button {
                    navigateToSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: actionButtonSize, height: actionButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glassCircleBackground(isHighlighted: false)
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("ios.dashboard.settings")
                .transition(MartenAnimation.fadeScale)
            }
        }
    }

    // MARK: - Pinboard Selector

    private var swipablePinboardSelector: some View {
        Button {
            isShowingPinboardPicker = true
        } label: {
            HStack(spacing: 6) {
                if let pinboard = selectedPinboard {
                    PinboardIndicator(
                        colorHex: pinboard.colorHex,
                        sign: pinboard.iconName,
                        size: 20
                    )
                    if container.lockStateStore.isLocked(pinboard.id) {
                        Image(
                            systemName: container.lockStateStore.canAccess(pinboard.id)
                                ? "lock.open.fill" : "lock.fill"
                        )
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
                } else {
                    ZStack {
                        Circle()
                            .fill(Color.secondary.opacity(0.15))
                            .frame(width: 20, height: 20)
                        Image(systemName: "tray.2.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                }

                Text(selectedPinboardTitle)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 24)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .glassChipBackground(isHighlighted: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select Pinboard")
        .accessibilityIdentifier("ios.dashboard.pinboardDropdown")
    }

    // MARK: - Pinboard Options Menu

    private func pinboardOptionsMenu(for pinboard: Pinboard) -> some View {
        Menu {
            pinboardContextMenuContent(for: pinboard)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: actionButtonSize, height: actionButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCircleBackground(isHighlighted: false)
        .accessibilityLabel("Pinboard Options")
        .accessibilityIdentifier("ios.dashboard.pinboardOptions")
    }

    // MARK: - Pinboard Context Menu

    @ViewBuilder
    private func pinboardContextMenuContent(for pinboard: Pinboard) -> some View {
        let isLocked = container.lockStateStore.isLocked(pinboard.id)
        let canAccess = container.lockStateStore.canAccess(pinboard.id)

        Button {
            pinboardEditorContext = PinboardEditorContext(
                objectIDURI: pinboard.objectID.uriRepresentation().absoluteString,
                name: pinboard.name,
                colorHex: pinboard.colorHex,
                iconName: pinboard.iconName
            )
        } label: {
            Label("Edit", systemImage: "pencil")
        }

        if container.sharingRepository != nil {
            let metadata = pinboard.shareMetadata
            let initialShareURL = metadata?.shareURL.flatMap(URL.init(string:))
            Button {
                pinboardShareContext = PinboardShareContext(
                    pinboardID: pinboard.objectID,
                    initialAccessControl: metadata?.accessControl ?? .onlyInvited,
                    initialPermission: metadata?.defaultPermission ?? .canMakeChanges,
                    initialShareURL: initialShareURL
                )
            } label: {
                Label(
                    pinboard.isShared ? "Manage Sharing" : "Share",
                    systemImage: "square.and.arrow.up"
                )
            }
        }

        Divider()

        if isLocked {
            Button {
                requestPinboardUnlock(pinboard)
            } label: {
                Label("Unlock", systemImage: "lock.open")
            }

            if canAccess {
                Button {
                    container.lockStateStore.lockNow(pinboardID: pinboard.id)
                } label: {
                    Label("Lock Now", systemImage: "lock.fill")
                }

                Button {
                    container.lockStateStore.setLock(false, for: pinboard.id)
                } label: {
                    Label("Disable Lock", systemImage: "lock.slash")
                }
            }
        } else {
            Button {
                container.lockStateStore.setLock(true, for: pinboard.id)
            } label: {
                Label("Lock Pinboard", systemImage: "lock")
            }
        }

        Divider()

        Button(role: .destructive) {
            pendingDeletePinboard = pinboard
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            // Filter button
            Button {
                isShowingFilters = true
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        searchModel?.hasActiveFilters ?? false ? Color.accentColor : .primary
                    )
                    .frame(width: actionButtonSize, height: actionButtonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .glassCircleBackground(isHighlighted: searchModel?.hasActiveFilters ?? false)
            .accessibilityLabel("Filters")
            .accessibilityIdentifier("ios.dashboard.filters")

            // Search bar with voice inline
            MartenGlassSearchBar(
                text: Binding(
                    get: { searchModel?.query ?? "" },
                    set: { searchModel?.query = $0 }
                ),
                prompt: "Search clips…",
                onClear: { searchModel?.clearSearchText() },
                focusRequest: $searchFocusRequest
            )

            // New Element button
            Button {
                isShowingQuickAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: actionButtonSize, height: actionButtonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .glassCircleBackground(isHighlighted: false)
            .accessibilityLabel("Quick Add")
            .accessibilityIdentifier("ios.dashboard.quickAdd")
        }
    }

    // MARK: - Selected Pinboard

    private var selectedPinboard: Pinboard? {
        guard let selectedID = container.selectedPinboardID else { return nil }
        return customPinboards.first(where: { $0.id == selectedID })
    }

    private var selectedPinboardTitle: String {
        guard let pinboard = selectedPinboard else { return "All" }
        return pinboardDisplayName(pinboard)
    }

    // MARK: - Filter Chips

    @ViewBuilder
    private func activeFiltersChips(searchModel: DashboardSearchModel) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if searchModel.dateFilter != .any {
                    filterChip(searchModel.dateFilter.label) {
                        searchModel.dateFilter = .any
                    }
                }

                ForEach(Array(searchModel.selectedTypes), id: \.rawValue) { type in
                    filterChip(type.label) {
                        searchModel.toggleType(type)
                    }
                }

                ForEach(Array(searchModel.selectedSourceApps), id: \.self) { appID in
                    filterChip(appID) {
                        searchModel.toggleSourceApp(appID)
                    }
                }

                ForEach(Array(searchModel.selectedSourceDevices), id: \.self) { device in
                    filterChip(device.label) {
                        searchModel.toggleSourceDevice(device)
                    }
                }

                Button {
                    searchModel.clearAllFilters()
                } label: {
                    Text("Clear All")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Search Results

    @ViewBuilder
    private func searchResultsContent(searchModel: DashboardSearchModel) -> some View {
        let visibleResults = searchModel.results.filter {
            isItemVisible($0, selectedPinboardID: container.selectedPinboardID)
        }

        ZStack {
            // Background dismissal area
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissSearch()
                }

            VStack(spacing: 0) {
                if searchModel.isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if visibleResults.isEmpty {
                    ContentUnavailableView.search(text: searchModel.query)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ItemCardGridView(
                        items: visibleResults,
                        selectionModel: DashboardSelectionModel(),
                        canReorder: false,
                        onTapItem: { item in handleItemTap(item) },
                        onCopyItem: { item in copyItems([item.objectID]) },
                        onCopyPlainTextItem: { item in copyItemsPlainText([item.objectID]) },
                        onPreviewItem: { item in handleItemPreview(item) },
                        onShareItem: { item in shareItems([item.objectID]) },
                        onMoveItem: { item in prepareMove([item.objectID]) },
                        onDeleteItem: { item in prepareDelete([item.objectID]) },
                        onReorderItems: { _ in }
                    )
                }
            }
        }
    }

    // MARK: - Dismiss Search

    private func dismissSearch() {
        withAnimation(MartenAnimation.quick) {
            searchModel?.clearSearchText()
            #if os(iOS)
                // Dismiss keyboard
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            #endif
        }
    }

    // MARK: - Helpers

    private var dashboardItemsSectionID: String {
        let selectedPinboardComponent = container.selectedPinboardID?.uuidString ?? "all"
        return "items-\(selectedPinboardComponent)-\(container.dashboardRefreshRevision)"
    }

    private var pinboardSignature: String {
        customPinboards
            .map(\.id.uuidString)
            .joined(separator: "|")
    }

    private var allItemsSignature: String {
        "\(allItems.count)-\(allItems.first?.objectID.uriRepresentation().absoluteString ?? "")"
    }

    private var moveTargetPinboards: [Pinboard] {
        customPinboards
    }

    private var displayPinboards: [Pinboard] {
        customPinboards
    }

    private func pinboardDisplayName(_ pinboard: Pinboard) -> String {
        return pinboard.name
    }

    private func reconcilePinboardState() {
        let validIDs = Set(customPinboards.map(\.id))
        container.lockStateStore.reconcile(validPinboardIDs: validIDs)

        if let selectedPinboardID = container.selectedPinboardID,
            !validIDs.contains(selectedPinboardID)
        {
            container.setSelectedPinboardID(nil)
        }
    }

    private var customPinboards: [Pinboard] {
        pinboards
            .filter { !$0.isSystemMarten }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var visibleAllItemsForSearchOptions: [ClipItem] {
        Array(allItems).filter { isItemVisible($0, selectedPinboardID: nil) }
    }

    private var isSelectedPinboardAwaitingUnlock: Bool {
        guard let selectedPinboardID = container.selectedPinboardID else { return false }
        guard container.lockStateStore.isLocked(selectedPinboardID) else { return false }
        return !container.lockStateStore.canAccess(selectedPinboardID)
    }

    private var selectedPinboardLockedContent: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(selectedPinboardTitle)
                .font(.headline.weight(.semibold))

            Text("This pinboard is locked.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let pinboard = selectedPinboard {
                Button {
                    requestPinboardUnlock(pinboard, selectAfterUnlock: true)
                } label: {
                    Label("Unlock", systemImage: "faceid")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(container.lockStateStore.isAuthenticating)
                .frame(maxWidth: 240)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentMargins(.top, 120, for: .scrollContent)
    }

    private func isItemVisible(_ item: ClipItem, selectedPinboardID: UUID?) -> Bool {
        if let selectedPinboardID {
            guard item.pinboards?.contains(where: { $0.id == selectedPinboardID }) ?? false else {
                return false
            }
            return container.lockStateStore.canAccess(selectedPinboardID)
        }

        let customAssignments = item.pinboards?.filter { !$0.isSystemMarten } ?? []
        guard !customAssignments.isEmpty else { return true }

        return !customAssignments.contains { pinboard in
            container.lockStateStore.isLocked(pinboard.id)
                && !container.lockStateStore.canAccess(pinboard.id)
        }
    }

    private func requestPinboardUnlock(_ pinboard: Pinboard, selectAfterUnlock: Bool = false) {
        Task { @MainActor in
            let unlocked = await container.lockStateStore.unlock(
                pinboardID: pinboard.id,
                pinboardName: pinboard.name
            )
            if unlocked, selectAfterUnlock {
                withAnimation(MartenAnimation.quick) {
                    container.setSelectedPinboardID(pinboard.id)
                }
            }
        }
    }

    private func handleItemTap(_ item: ClipItem) {
        if selectionModel.isSelectionMode {
            selectionModel.toggleSelection(for: item)
            return
        }

        // Default behavior: copy to clipboard
        copyItems([item.objectID])
    }

    private func handleItemPreview(_ item: ClipItem) {
        searchModel?.donateOpenItem(item)

        switch item.itemTypeValue {
        case .text, .richText:
            activeDestination = .richText(item.objectID)
        case .image:
            activeDestination = .image(item.objectID)
        case .code:
            activeDestination = .code(item.objectID)
        case .url:
            activeDestination = .url(item.objectID)
        default:
            // For other types, copy to clipboard
            copyItems([item.objectID])
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
        let text =
            items
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

        // Show toast notification
        let message = objectIDs.count == 1 ? "Copied" : "Copied \(objectIDs.count) items"
        toastController.show(message, systemImage: "doc.on.doc.fill")

        Task {
            try? await container.commandService.markItemsUsed(objectIDs: objectIDs)
        }
    }

    private func copyItemsPlainText(_ objectIDs: [NSManagedObjectID]) {
        let items = resolveItems(from: objectIDs)
        let text =
            items
            .compactMap { item in
                // Always get plain text, stripping any rich formatting
                if let plainText = item.plainTextContent?.trimmingCharacters(
                    in: .whitespacesAndNewlines), !plainText.isEmpty
                {
                    return plainText
                }
                return item.primaryText?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        guard !text.isEmpty else { return }
        #if canImport(UIKit)
            UIPasteboard.general.string = text
        #endif

        // Show toast notification
        let message =
            objectIDs.count == 1
            ? "Copied as plain text" : "Copied \(objectIDs.count) items as plain text"
        toastController.show(message, systemImage: "textformat")

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
            let combinedText =
                items
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

    private func reorderItems(_ objectIDs: [NSManagedObjectID]) {
        Task {
            do {
                try container.clipItemStore.reorderItems(objectIDs: objectIDs)
            } catch {
                print("Error reordering items: \(error)")
            }
        }
    }

    private var integrationsOnboardingBanner: some View {
        MartenGlassSurface(cornerRadius: 14, padding: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Integrations")
                        .font(.subheadline.weight(.semibold))
                    Text("Share Extension, Keyboard, Widgets & Siri")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button("Setup") {
                    navigateToSettings = true
                }
                .font(.caption.weight(.bold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    withAnimation(MartenAnimation.smooth) {
                        container.dismissIntegrationsOnboarding()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
    }

    private func filterChip(_ title: String, removeAction: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Button {
                removeAction()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(minWidth: 24, minHeight: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .glassChipBackground(isHighlighted: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Filter: \(title)")
        .accessibilityHint("Double tap to remove filter")
    }
}

private struct DashboardItemsSection: View {
    @FetchRequest private var items: FetchedResults<ClipItem>
    let selectedPinboardID: UUID?
    let isItemVisible: (ClipItem) -> Bool
    @Bindable var selectionModel: DashboardSelectionModel
    let onTapItem: (ClipItem) -> Void
    let onCopyItem: (ClipItem) -> Void
    let onCopyPlainTextItem: (ClipItem) -> Void
    let onPreviewItem: (ClipItem) -> Void
    let onShareItem: (ClipItem) -> Void
    let onMoveItem: (ClipItem) -> Void
    let onDeleteItem: (ClipItem) -> Void
    let onReorderItems: ([NSManagedObjectID]) -> Void
    let onVisibleObjectIDsChanged: (Set<NSManagedObjectID>) -> Void

    init(
        selectedPinboardID: UUID?,
        isItemVisible: @escaping (ClipItem) -> Bool,
        selectionModel: DashboardSelectionModel,
        onTapItem: @escaping (ClipItem) -> Void,
        onCopyItem: @escaping (ClipItem) -> Void,
        onCopyPlainTextItem: @escaping (ClipItem) -> Void,
        onPreviewItem: @escaping (ClipItem) -> Void,
        onShareItem: @escaping (ClipItem) -> Void,
        onMoveItem: @escaping (ClipItem) -> Void,
        onDeleteItem: @escaping (ClipItem) -> Void,
        onReorderItems: @escaping ([NSManagedObjectID]) -> Void,
        onVisibleObjectIDsChanged: @escaping (Set<NSManagedObjectID>) -> Void
    ) {
        _items = FetchRequest(
            fetchRequest: dashboardItemsFetchRequest(selectedPinboardID: selectedPinboardID),
            animation: .default
        )
        self.selectedPinboardID = selectedPinboardID
        self.isItemVisible = isItemVisible
        self.selectionModel = selectionModel
        self.onTapItem = onTapItem
        self.onCopyItem = onCopyItem
        self.onCopyPlainTextItem = onCopyPlainTextItem
        self.onPreviewItem = onPreviewItem
        self.onShareItem = onShareItem
        self.onMoveItem = onMoveItem
        self.onDeleteItem = onDeleteItem
        self.onReorderItems = onReorderItems
        self.onVisibleObjectIDsChanged = onVisibleObjectIDsChanged
    }

    var body: some View {
        ItemCardGridView(
            items: visibleItems,
            selectionModel: selectionModel,
            canReorder: selectedPinboardID != nil,
            contentInsets: EdgeInsets(top: 80, leading: 0, bottom: 100, trailing: 0),
            onTapItem: onTapItem,
            onCopyItem: onCopyItem,
            onCopyPlainTextItem: onCopyPlainTextItem,
            onPreviewItem: onPreviewItem,
            onShareItem: onShareItem,
            onMoveItem: onMoveItem,
            onDeleteItem: onDeleteItem,
            onReorderItems: onReorderItems
        )
        .onAppear {
            onVisibleObjectIDsChanged(Set(visibleItems.map(\.objectID)))
        }
        .onChange(of: itemsSignature) {
            onVisibleObjectIDsChanged(Set(visibleItems.map(\.objectID)))
        }
    }

    private var visibleItems: [ClipItem] {
        Array(items).filter(isItemVisible)
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
        predicates.append(
            NSPredicate(format: "ANY pinboards.id == %@", selectedPinboardID as CVarArg))
    }

    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

    // In pinboards: use displayOrder for manual reordering
    // In "All": use modifiedAt for chronological sorting (most recent first)
    if selectedPinboardID != nil {
        request.sortDescriptors = [
            NSSortDescriptor(key: "displayOrder", ascending: false),
            NSSortDescriptor(key: "modifiedAt", ascending: false),
        ]
    } else {
        request.sortDescriptors = [
            NSSortDescriptor(key: "modifiedAt", ascending: false)
        ]
    }

    request.returnsObjectsAsFaults = false
    request.relationshipKeyPathsForPrefetching = ["representations", "pinboards", "linkPreview"]

    return request
}

private enum ActiveDestination: Identifiable {
    case richText(NSManagedObjectID)
    case image(NSManagedObjectID)
    case code(NSManagedObjectID)
    case url(NSManagedObjectID)

    var id: String {
        switch self {
        case .richText(let objectID):
            return "rich-\(objectID.uriRepresentation().absoluteString)"
        case .image(let objectID):
            return "image-\(objectID.uriRepresentation().absoluteString)"
        case .code(let objectID):
            return "code-\(objectID.uriRepresentation().absoluteString)"
        case .url(let objectID):
            return "url-\(objectID.uriRepresentation().absoluteString)"
        }
    }
}

// MARK: - Pinboard Editor & Share Context

private struct PinboardEditorContext: Identifiable {
    let objectIDURI: String
    let name: String
    let colorHex: String
    let iconName: String?

    var id: String { objectIDURI }
}

private struct PinboardShareContext: Identifiable {
    let pinboardID: NSManagedObjectID
    let initialAccessControl: ShareAccessControl
    let initialPermission: SharePermission
    let initialShareURL: URL?

    var id: String { pinboardID.uriRepresentation().absoluteString }
}

// MARK: - Pinboard Picker Sheet

struct PinboardPickerSheet: View {
    let container: MartenIOSAppContainer
    let pinboards: [Pinboard]
    let lockStateStore: PinboardLockStateStore
    let selectedPinboardID: UUID?
    let onSelect: (UUID?) -> Void
    let onEdit: (Pinboard) -> Void
    let onShare: (Pinboard) -> Void
    let onDelete: (Pinboard) -> Void
    let onReorder: ([NSManagedObjectID]) -> Void
    let onCreate: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var orderedPinboards: [Pinboard] = []

    private let rowCornerRadius: CGFloat = 999

    private var estimatedSheetHeight: CGFloat {
        let baseHeight: CGFloat = 140
        let estimatedRowHeight: CGFloat = 62
        let rowCount = CGFloat(orderedPinboards.count + 1)
        let estimated = baseHeight + (rowCount * estimatedRowHeight)
        return min(max(estimated, 260), 560)
    }

    var body: some View {
        NavigationStack {
            List {
                // "All" row
                Button {
                    onSelect(nil)
                    dismiss()
                } label: {
                    PinboardSelectionRow(
                        leading: .all,
                        title: "All",
                        showsSelectionCheckmark: true,
                        isSelected: selectedPinboardID == nil,
                        cornerRadius: rowCornerRadius
                    )
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                // Pinboard rows
                ForEach(orderedPinboards, id: \.objectID) { pinboard in
                    pinboardRow(pinboard)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            // Delete action
                            Button(role: .destructive) {
                                onDelete(pinboard)
                            } label: {
                                MartenSwipeActionIcon(systemName: "trash", backgroundColor: .red)
                            }
                            .tint(.red)
                            .accessibilityLabel("Delete")
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            // Edit action
                            Button {
                                onEdit(pinboard)
                            } label: {
                                MartenSwipeActionIcon(systemName: "pencil", backgroundColor: .blue)
                            }
                            .tint(.blue)
                            .accessibilityLabel("Edit")

                            // Share action
                            if container.sharingRepository != nil {
                                Button {
                                    onShare(pinboard)
                                } label: {
                                    MartenSwipeActionIcon(
                                        systemName: "square.and.arrow.up",
                                        backgroundColor: .green
                                    )
                                }
                                .tint(.green)
                                .accessibilityLabel("Share")
                            }

                            // Lock/Unlock actions
                            let isLocked = lockStateStore.isLocked(pinboard.id)
                            let canAccess = lockStateStore.canAccess(pinboard.id)

                            if isLocked {
                                if canAccess {
                                    Button {
                                        lockStateStore.lockNow(pinboardID: pinboard.id)
                                    } label: {
                                        MartenSwipeActionIcon(
                                            systemName: "lock.fill", backgroundColor: .orange)
                                    }
                                    .tint(.orange)
                                    .accessibilityLabel("Lock")
                                }

                                Button {
                                    lockStateStore.setLock(false, for: pinboard.id)
                                } label: {
                                    MartenSwipeActionIcon(
                                        systemName: "lock.slash", backgroundColor: .gray)
                                }
                                .tint(.gray)
                                .accessibilityLabel("Disable Lock")
                            } else {
                                Button {
                                    lockStateStore.setLock(true, for: pinboard.id)
                                } label: {
                                    MartenSwipeActionIcon(
                                        systemName: "lock", backgroundColor: .orange)
                                }
                                .tint(.orange)
                                .accessibilityLabel("Lock")
                            }
                        }
                }
                .onMove { source, destination in
                    orderedPinboards.move(fromOffsets: source, toOffset: destination)
                    onReorder(orderedPinboards.map(\.objectID))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(platformColor: .platformSystemGroupedBackground))
            .navigationTitle("Pinboards")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            onCreate()
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3)
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                orderedPinboards = pinboards
            }
        }
        .presentationDetents([.height(estimatedSheetHeight)])
        .presentationDragIndicator(.visible)
    }

    private func pinboardRow(_ pinboard: Pinboard) -> some View {
        let isLocked = lockStateStore.isLocked(pinboard.id)
        let canAccess = lockStateStore.canAccess(pinboard.id)

        return Button {
            if isLocked && !canAccess {
                Task { @MainActor in
                    let unlocked = await lockStateStore.unlock(
                        pinboardID: pinboard.id,
                        pinboardName: pinboard.name
                    )
                    guard unlocked else { return }
                    onSelect(pinboard.id)
                    dismiss()
                }
            } else {
                onSelect(pinboard.id)
                dismiss()
            }
        } label: {
            PinboardSelectionRow(
                leading: .pinboard(colorHex: pinboard.colorHex, sign: pinboard.iconName),
                title: pinboard.name,
                showsSharedBadge: pinboard.isShared,
                showsSelectionCheckmark: true,
                isSelected: selectedPinboardID == pinboard.id,
                lockState: .init(isLocked: isLocked, canAccess: canAccess),
                cornerRadius: rowCornerRadius
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Fetch Request

func searchAllItemsFetchRequest() -> NSFetchRequest<ClipItem> {
    let request = ClipItem.fetchRequest()
    request.predicate = NSPredicate(format: "isTransient == NO")
    request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
    request.fetchLimit = 500
    request.returnsObjectsAsFaults = false
    return request
}

// MARK: - Extensions

extension ClipItemDateFilter {
    var label: String {
        switch self {
        case .any: return "Any Time"
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .last7Days: return "Last 7 Days"
        case .last30Days: return "Last 30 Days"
        }
    }
}

extension ItemType {
    var label: String {
        switch self {
        case .text: return "Text"
        case .richText: return "Rich Text"
        case .image: return "Image"
        case .file: return "File"
        case .url: return "Link"
        case .code: return "Code"
        case .color: return "Color"
        case .mixed: return "Mixed"
        }
    }
}

extension ClipItemSourceDevice {
    var label: String {
        switch self {
        case .thisDevice: return "This Device"
        case .unknown: return "Unknown"
        case .named(let name): return name
        }
    }
}

// MARK: - Search Filters Sheet

struct SearchFiltersSheet: View {
    @Bindable var searchModel: DashboardSearchModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Date") {
                    ForEach(
                        [ClipItemDateFilter.any, .today, .yesterday, .last7Days, .last30Days],
                        id: \.self
                    ) { filter in
                        Button {
                            searchModel.dateFilter = filter
                        } label: {
                            HStack {
                                Text(filter.label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if searchModel.dateFilter == filter {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Type") {
                    ForEach(
                        [ItemType.text, .richText, .image, .file, .url, .code, .color], id: \.self
                    ) { type in
                        Button {
                            searchModel.toggleType(type)
                        } label: {
                            HStack {
                                Text(type.label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if searchModel.selectedTypes.contains(type) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !searchModel.deviceOptions.isEmpty {
                    Section("Source Device") {
                        ForEach(searchModel.deviceOptions) { device in
                            Button {
                                searchModel.toggleSourceDevice(device.value)
                            } label: {
                                HStack {
                                    Text(device.title)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(device.count)")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                    if searchModel.selectedSourceDevices.contains(device.value) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if searchModel.hasActiveFilters {
                    Section {
                        Button("Clear All Filters") {
                            searchModel.clearAllFilters()
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Filters")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
