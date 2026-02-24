import CoreData
import MartenCore
import SwiftUI

struct MartenIOSDashboardView: View {
    @Bindable var container: MartenIOSAppContainer

    @FetchRequest(fetchRequest: dashboardPinboardFetchRequest())
    private var pinboards: FetchedResults<Pinboard>

    @FetchRequest(fetchRequest: searchAllItemsFetchRequest())
    private var allItems: FetchedResults<ClipItem>

    @State private var viewModel = DashboardViewModel()

    @ScaledMetric(relativeTo: .headline) private var actionButtonSize: CGFloat = 44

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if viewModel.isSelectedPinboardAwaitingUnlock(
                    selectedPinboardID: container.selectedPinboardID,
                    lockStateStore: container.lockStateStore
                ) {
                    DashboardLockedPinboardView(
                        title: selectedPinboardTitle,
                        isAuthenticating: container.lockStateStore.isAuthenticating,
                        onUnlock: {
                            guard let pinboard = selectedPinboard else { return }
                            viewModel.requestPinboardUnlock(
                                pinboard,
                                lockStateStore: container.lockStateStore
                            ) {
                                withAnimation(MartenAnimation.quick) {
                                    container.setSelectedPinboardID(pinboard.id)
                                }
                            }
                        },
                        onSwipe: { offset in
                            viewModel.advancePinboardSelection(by: offset, container: container, customPinboards: customPinboards)
                        }
                    )
                } else if let searchModel = viewModel.searchModel, searchModel.isSearchActive {
                    searchResultsContent(searchModel: searchModel)
                } else {
                    DashboardItemsSection(
                        selectedPinboardID: container.selectedPinboardID,
                        isItemVisible: { item in
                            viewModel.isItemVisible(
                                item,
                                selectedPinboardID: container.selectedPinboardID,
                                lockStateStore: container.lockStateStore
                            )
                        },
                        selectionModel: viewModel.selectionModel,
                        onTapItem: { item in
                            viewModel.handleItemTap(item, container: container)
                        },
                        onCopyItem: { item in
                            viewModel.copyItems([item.objectID], container: container)
                        },
                        onCopyPlainTextItem: { item in
                            viewModel.copyItemsPlainText([item.objectID], container: container)
                        },
                        onPreviewItem: { item in
                            viewModel.handleItemPreview(item, container: container)
                        },
                        onEditItem: { item in
                            viewModel.handleItemEdit(item, container: container)
                        },
                        onTogglePinItem: { item in
                            viewModel.togglePin(item, container: container)
                        },
                        onShareItem: { item in
                            viewModel.shareItems([item.objectID], container: container)
                        },
                        onMoveItem: { item in
                            viewModel.prepareMove([item.objectID])
                        },
                        onDeleteItem: { item in
                            viewModel.prepareDelete([item.objectID])
                        },
                        onReorderItems: { objectIDs in
                            viewModel.reorderItems(objectIDs, container: container)
                        },
                        onSwipeToNextPinboard: {
                            viewModel.advancePinboardSelection(by: 1, container: container, customPinboards: customPinboards)
                        },
                        onSwipeToPreviousPinboard: {
                            viewModel.advancePinboardSelection(by: -1, container: container, customPinboards: customPinboards)
                        },
                        onVisibleObjectIDsChanged: { visibleIDs in
                            if viewModel.selectionModel.isSelectionMode {
                                viewModel.selectionModel.selectedObjectIDs =
                                    viewModel.selectionModel.selectedObjectIDs.intersection(visibleIDs)
                            }
                        }
                    )
                    .id(dashboardItemsSectionID)
                    .transition(.displaceDistortion(direction: viewModel.swipeDirection))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()

            DashboardGradientFadesView()

            VStack(spacing: 0) {
                DashboardTopBarView(
                    isSelectionMode: viewModel.selectionModel.isSelectionMode,
                    selectedCount: viewModel.selectionModel.selectedCount,
                    selectedPinboardTitle: selectedPinboardTitle,
                    currentPinboardItemCount: currentPinboardItemCount,
                    selectedPinboard: selectedPinboard,
                    actionButtonSize: actionButtonSize,
                    onToggleSelectionMode: {
                        withAnimation(MartenAnimation.smooth) {
                            viewModel.selectionModel.toggleSelectionMode()
                        }
                    },
                    onOpenSettings: {
                        viewModel.navigateToSettings = true
                    },
                    pinboardMenuContent: { pinboard in
                        pinboardContextMenuContent(for: pinboard)
                    }
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)

                if container.shouldShowIntegrationsOnboarding {
                    DashboardIntegrationsOnboardingBanner(
                        onSetup: { viewModel.navigateToSettings = true },
                        onDismiss: {
                            withAnimation(MartenAnimation.smooth) {
                                container.dismissIntegrationsOnboarding()
                            }
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(MartenAnimation.fadeScale)
                }
            }

            VStack {
                Spacer()
                if viewModel.selectionModel.isSelectionMode && viewModel.selectionModel.hasSelection {
                    DashboardSelectionActionBar(
                        selectedCount: viewModel.selectionModel.selectedCount,
                        onCopy: {
                            viewModel.copyItems(Array(viewModel.selectionModel.selectedObjectIDs), container: container)
                        },
                        onMove: {
                            viewModel.prepareMove(Array(viewModel.selectionModel.selectedObjectIDs))
                        },
                        onShare: {
                            viewModel.shareItems(Array(viewModel.selectionModel.selectedObjectIDs), container: container)
                        },
                        onDelete: {
                            viewModel.prepareDelete(Array(viewModel.selectionModel.selectedObjectIDs))
                        },
                        onCancel: {
                            withAnimation(MartenAnimation.smooth) {
                                viewModel.selectionModel.toggleSelectionMode()
                            }
                        }
                    )
                } else {
                    DashboardBottomBarView(
                        selectedPinboard: selectedPinboard,
                        actionButtonSize: actionButtonSize,
                        isSearchExpanded: $viewModel.isSearchExpanded,
                        searchFocusRequest: $viewModel.searchFocusRequest,
                        searchQuery: Binding(
                            get: { viewModel.searchModel?.query ?? "" },
                            set: { viewModel.searchModel?.query = $0 }
                        ),
                        hasActiveFilters: viewModel.searchModel?.hasActiveFilters ?? false,
                        onOpenPinboardPicker: { viewModel.isShowingPinboardPicker = true },
                        onShowFilters: { viewModel.isShowingFilters = true },
                        onShowQuickAdd: { viewModel.isShowingQuickAdd = true },
                        onCloseSearch: { viewModel.closeSearch() }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.opacity)
                }
            }
            .animation(
                MartenAnimation.smooth,
                value: viewModel.selectionModel.isSelectionMode && viewModel.selectionModel.hasSelection
            )
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .toast(controller: viewModel.toastController)
        .navigationDestination(isPresented: $viewModel.navigateToSettings) {
            MartenIOSSettingsView(container: container)
        }
        .sheet(isPresented: $viewModel.isShowingPinboardPicker) {
            PinboardPickerSheet(
                container: container,
                pinboards: customPinboards,
                lockStateStore: container.lockStateStore,
                selectedPinboardID: container.selectedPinboardID,
                onSelect: { pinboardID in
                    withAnimation(MartenAnimation.quick) {
                        container.setSelectedPinboardID(pinboardID)
                    }
                },
                onEdit: { pinboard in
                    viewModel.isShowingPinboardPicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        viewModel.pinboardEditorContext = DashboardPinboardEditorContext(
                            objectIDURI: pinboard.objectID.uriRepresentation().absoluteString,
                            name: pinboard.name,
                            colorHex: pinboard.colorHex,
                            iconName: pinboard.iconName
                        )
                    }
                },
                onShare: { pinboard in
                    guard container.canOpenShareSettings(for: pinboard) else { return }
                    viewModel.isShowingPinboardPicker = false
                    if container.sharingRepository != nil {
                        let metadata = pinboard.shareMetadata
                        let initialShareURL = metadata?.shareURL.flatMap(URL.init(string:))
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            viewModel.pinboardShareContext = DashboardPinboardShareContext(
                                pinboardID: pinboard.objectID,
                                pinboardUUID: pinboard.id,
                                initialAccessControl: metadata?.accessControl ?? .onlyInvited,
                                initialPermission: metadata?.defaultPermission ?? .canMakeChanges,
                                initialShareURL: initialShareURL
                            )
                        }
                    }
                },
                onDelete: { pinboard in
                    viewModel.isShowingPinboardPicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        viewModel.pendingDeletePinboard = pinboard
                    }
                },
                onReorder: { orderedIDs in
                    try? container.clipItemStore.reorderPinboards(orderedIDs: orderedIDs)
                },
                onCreate: {
                    viewModel.isShowingPinboardCreation = true
                }
            )
        }
        .sheet(isPresented: $viewModel.isShowingPinboardManagement) {
            PinboardManagementSheet(container: container)
        }
        .sheet(isPresented: $viewModel.isShowingPinboardCreation) {
            PinboardEditorSheet(mode: .create) { name, colorHex, iconName in
                Task {
                    await container.createPinboard(name: name, colorHex: colorHex, iconName: iconName)
                }
            }
        }
        .sheet(isPresented: $viewModel.isShowingQuickAdd) {
            QuickAddMenuSheet(container: container)
        }
        .sheet(isPresented: $viewModel.isShowingFilters) {
            if let searchModel = viewModel.searchModel {
                SearchFiltersSheet(searchModel: searchModel)
            }
        }
        .sheet(isPresented: $viewModel.isShowingMoveSheet) {
            MoveToPinboardSheet(
                pinboards: customPinboards,
                lockStateStore: container.lockStateStore
            ) { destination in
                Task {
                    switch destination {
                    case .all:
                        await container.moveItemsToAll(viewModel.moveObjectIDs)
                    case .pinboard(let pinboard):
                        await container.moveItems(viewModel.moveObjectIDs, toPinboardID: pinboard.objectID)
                    }
                    viewModel.selectionModel.clearSelection()
                }
            }
        }
        .sheet(item: $viewModel.shareSheetContext) { context in
            ActivityView(activityItems: context.items)
        }
        .sheet(item: $viewModel.activePreviewDestination) { destination in
            let resolver = CoreDataDashboardClipItemResolver(viewContext: container.persistenceController.viewContext)
            switch destination {
            case .text(let objectID):
                if let item = resolver.item(with: objectID) {
                    TextViewerSheet(item: item) {
                        viewModel.transitionFromPreviewToEdit(.richText(objectID))
                    }
                }
            case .image(let objectID):
                if let item = resolver.item(with: objectID) {
                    ImageViewerSheet(item: item, mode: .preview, onEdit: {
                        viewModel.transitionFromPreviewToEdit(.image(objectID))
                    })
                }
            case .code(let objectID):
                if let item = resolver.item(with: objectID) {
                    CodeViewerSheet(item: item) {
                        viewModel.transitionFromPreviewToEdit(.code(objectID))
                    }
                }
            case .url(let objectID):
                if let item = resolver.item(with: objectID) {
                    URLViewerSheet(item: item) {
                        viewModel.transitionFromPreviewToEdit(.url(objectID))
                    }
                }
            case .color(let objectID):
                if let item = resolver.item(with: objectID) {
                    ColorViewerSheet(item: item) {
                        viewModel.transitionFromPreviewToEdit(.color(objectID))
                    }
                }
            }
        }
        .sheet(item: $viewModel.activeEditDestination) { destination in
            let resolver = CoreDataDashboardClipItemResolver(viewContext: container.persistenceController.viewContext)
            switch destination {
            case .richText(let objectID):
                if let item = resolver.item(with: objectID) {
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
                if let item = resolver.item(with: objectID) {
                    ImageViewerSheet(
                        item: item,
                        mode: .edit,
                        onSaveEdits: { editedImageData in
                        Task {
                            await container.updateImageItem(
                                objectID: objectID,
                                imageData: editedImageData
                            )
                        }
                    })
                }
            case .code(let objectID):
                if let item = resolver.item(with: objectID) {
                    CodeEditorSheet(item: item) { text in
                        Task {
                            await container.updateTextItem(
                                objectID: objectID,
                                newText: text
                            )
                        }
                    }
                }
            case .url(let objectID):
                if let item = resolver.item(with: objectID) {
                    LinkEditorSheet(item: item) { text in
                        Task {
                            await container.updateTextItem(
                                objectID: objectID,
                                newText: text
                            )
                        }
                    }
                }
            case .color(let objectID):
                if let item = resolver.item(with: objectID) {
                    ColorEditorSheet(item: item) { text in
                        Task {
                            await container.updateTextItem(
                                objectID: objectID,
                                newText: text
                            )
                        }
                    }
                }
            }
        }
        .alert(
            "Delete Items?",
            isPresented: $viewModel.isShowingDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                viewModel.confirmDelete(container: container)
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelDelete()
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(item: $viewModel.pinboardEditorContext) { context in
            PinboardEditorSheet(
                mode: .edit,
                initialName: context.name,
                initialColorHex: context.colorHex,
                initialIconName: context.iconName
            ) { updatedName, updatedColorHex, updatedIconName in
                guard
                    let url = URL(string: context.objectIDURI),
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
        .sheet(item: $viewModel.pinboardShareContext) { context in
            if let sharingRepository = container.sharingRepository {
                ShareSettingsSheet(
                    pinboardID: context.pinboardID,
                    sharingRepository: sharingRepository,
                    initialAccessControl: context.initialAccessControl,
                    initialPermission: context.initialPermission,
                    initialShareURL: context.initialShareURL,
                    isPinboardLocked: { container.lockStateStore.isLocked(context.pinboardUUID) }
                )
            }
        }
        .alert(
            "Delete Pinboard?",
            isPresented: Binding(
                get: { viewModel.pendingDeletePinboard != nil },
                set: { if !$0 { viewModel.pendingDeletePinboard = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                guard let pinboard = viewModel.pendingDeletePinboard else { return }
                Task {
                    await container.deletePinboard(pinboard)
                }
                viewModel.pendingDeletePinboard = nil
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingDeletePinboard = nil
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
            await viewModel.bootstrapIfNeeded(
                container: container,
                allItems: Array(allItems),
                customPinboards: customPinboards
            )
        }
        .onChange(of: pinboardSignature) {
            viewModel.reconcilePinboardState(container: container, customPinboards: customPinboards)
        }
        .onChange(of: allItemsSignature) {
            if let model = viewModel.searchModel {
                model.updateOptions(
                    from: viewModel.visibleAllItemsForSearchOptions(container: container, allItems: Array(allItems))
                )
            }
        }
        .onAppear {
            if let action = container.pendingWidgetAction {
                Task { @MainActor in
                    await viewModel.handleWidgetAction(action, container: container)
                }
            }
        }
        .onChange(of: container.pendingWidgetAction) { _, newValue in
            guard let action = newValue else { return }
            Task { @MainActor in
                await viewModel.handleWidgetAction(action, container: container)
            }
        }
    }

    @ViewBuilder
    private func pinboardContextMenuContent(for pinboard: Pinboard) -> some View {
        let supportsLock = !pinboard.isShared
        let isLocked = supportsLock && container.lockStateStore.isLocked(pinboard.id)
        let canAccess = !isLocked || container.lockStateStore.canAccess(pinboard.id)

        Button {
            viewModel.pinboardEditorContext = DashboardPinboardEditorContext(
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
            if pinboard.isShared {
                Button {
                    guard container.canOpenShareSettings(for: pinboard) else { return }
                    viewModel.pinboardShareContext = DashboardPinboardShareContext(
                        pinboardID: pinboard.objectID,
                        pinboardUUID: pinboard.id,
                        initialAccessControl: metadata?.accessControl ?? .onlyInvited,
                        initialPermission: metadata?.defaultPermission ?? .canMakeChanges,
                        initialShareURL: initialShareURL
                    )
                } label: {
                    Label("Manage Sharing", systemImage: "square.and.arrow.up")
                }
            } else if !isLocked {
                Button {
                    guard container.canOpenShareSettings(for: pinboard) else { return }
                    viewModel.pinboardShareContext = DashboardPinboardShareContext(
                        pinboardID: pinboard.objectID,
                        pinboardUUID: pinboard.id,
                        initialAccessControl: metadata?.accessControl ?? .onlyInvited,
                        initialPermission: metadata?.defaultPermission ?? .canMakeChanges,
                        initialShareURL: initialShareURL
                    )
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }

        Divider()

        if supportsLock {
            if isLocked {
                Button {
                    viewModel.requestPinboardUnlock(pinboard, lockStateStore: container.lockStateStore) { }
                } label: {
                    Label("Unlock", systemImage: "lock.open")
                }

                if canAccess {
                    Button {
                        container.lockPinboardNow(pinboard)
                    } label: {
                        Label("Lock Now", systemImage: "lock.fill")
                    }

                    Button {
                        container.setPinboardLock(false, for: pinboard)
                    } label: {
                        Label("Disable Lock", systemImage: "lock.slash")
                    }
                }
            } else {
                Button {
                    container.setPinboardLock(true, for: pinboard)
                } label: {
                    Label("Lock Pinboard", systemImage: "lock")
                }
            }
            Divider()
        }

        Button(role: .destructive) {
            viewModel.pendingDeletePinboard = pinboard
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func searchResultsContent(searchModel: DashboardSearchModel) -> some View {
        let visibleResults = searchModel.results.filter {
            viewModel.isItemVisible(
                $0,
                selectedPinboardID: container.selectedPinboardID,
                lockStateStore: container.lockStateStore
            )
        }

        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.dismissSearch()
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
                        allowPinning: container.selectedPinboardID != nil,
                        contentInsets: EdgeInsets(top: 80, leading: 0, bottom: 100, trailing: 0),
                        onTapItem: { item in viewModel.handleItemTap(item, container: container) },
                        onCopyItem: { item in viewModel.copyItems([item.objectID], container: container) },
                        onCopyPlainTextItem: { item in viewModel.copyItemsPlainText([item.objectID], container: container) },
                        onPreviewItem: { item in viewModel.handleItemPreview(item, container: container) },
                        onEditItem: { item in viewModel.handleItemEdit(item, container: container) },
                        onTogglePinItem: { item in viewModel.togglePin(item, container: container) },
                        onShareItem: { item in viewModel.shareItems([item.objectID], container: container) },
                        onMoveItem: { item in viewModel.prepareMove([item.objectID]) },
                        onDeleteItem: { item in viewModel.prepareDelete([item.objectID]) },
                        onReorderItems: { _ in },
                        onSwipeToNextPinboard: {
                            viewModel.advancePinboardSelection(by: 1, container: container, customPinboards: customPinboards)
                        },
                        onSwipeToPreviousPinboard: {
                            viewModel.advancePinboardSelection(by: -1, container: container, customPinboards: customPinboards)
                        }
                    )
                }
            }
        }
    }

    private var dashboardItemsSectionID: String {
        let selectedPinboardComponent = container.selectedPinboardID?.uuidString ?? "all"
        return "items-\(selectedPinboardComponent)-\(container.dashboardRefreshRevision)"
    }

    private var customPinboards: [Pinboard] {
        viewModel.customPinboards(from: Array(pinboards))
    }

    private var selectedPinboard: Pinboard? {
        viewModel.selectedPinboard(from: customPinboards, selectedPinboardID: container.selectedPinboardID)
    }

    private var selectedPinboardTitle: String {
        viewModel.selectedPinboardTitle(selectedPinboard: selectedPinboard)
    }

    private var currentPinboardItemCount: Int {
        viewModel.currentPinboardItemCount(
            allItems: Array(allItems),
            selectedPinboardID: container.selectedPinboardID,
            lockStateStore: container.lockStateStore
        )
    }

    private var pinboardSignature: String {
        customPinboards
            .map { "\($0.id.uuidString):\($0.isShared ? "shared" : "private")" }
            .joined(separator: "|")
    }

    private var allItemsSignature: String {
        "\(allItems.count)-\(allItems.first?.objectID.uriRepresentation().absoluteString ?? "")"
    }
}
