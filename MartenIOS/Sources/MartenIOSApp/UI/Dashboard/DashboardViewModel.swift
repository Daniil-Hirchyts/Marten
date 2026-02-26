import CoreData
import Foundation
import MartenCore
import Observation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class DashboardViewModel {
    var selectionModel = DashboardSelectionModel()
    var toastController = ToastController()

    var searchModel: DashboardSearchModel?
    var searchFocusRequest = false

    var isShowingPinboardManagement = false
    var isShowingPinboardCreation = false
    var isShowingPinboardPicker = false
    var isShowingQuickAdd = false
    var isShowingMoveSheet = false
    var isShowingFilters = false

    var moveObjectIDs: [NSManagedObjectID] = []
    var shareSheetContext: DashboardShareSheetContext?
    var pendingDeleteObjectIDs: [NSManagedObjectID] = []
    var isShowingDeleteConfirmation = false
    var activePreviewDestination: DashboardPreviewDestination?
    var activeEditDestination: DashboardEditDestination?
    var navigateToSettings = false
    var pinboardEditorContext: DashboardPinboardEditorContext?
    var pinboardShareContext: DashboardPinboardShareContext?
    var pendingDeletePinboard: Pinboard?

    var isSearchExpanded = false
    var swipeDirection: Int = 1

    private let itemActions: DashboardItemActionService

    init(dependencies: DashboardDependencies = .live) {
        itemActions = DashboardItemActionService(dependencies: dependencies)
    }

    func bootstrapIfNeeded(container: MartenIOSAppContainer, allItems: [ClipItem], customPinboards: [Pinboard]) async {
        if searchModel == nil {
            searchModel = DashboardSearchModel(
                queryService: ClipItemQueryService(store: container.clipItemStore)
            )
        }
        await container.refreshPendingLinkPreviews()
        reconcilePinboardState(container: container, customPinboards: customPinboards)
        searchModel?.updateOptions(from: visibleAllItemsForSearchOptions(container: container, allItems: allItems))
    }

    func handleWidgetAction(_ action: MartenIOSAppContainer.WidgetAction, container: MartenIOSAppContainer) async {
        container.pendingWidgetAction = nil

        switch action {
        case .search:
            withAnimation(MartenAnimation.smooth) {
                isSearchExpanded = true
            }
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

    func customPinboards(from pinboards: [Pinboard]) -> [Pinboard] {
        pinboards
            .filter { !$0.isSystemMarten }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func selectedPinboard(from customPinboards: [Pinboard], selectedPinboardID: UUID?) -> Pinboard? {
        guard let selectedPinboardID else { return nil }
        return customPinboards.first(where: { $0.id == selectedPinboardID })
    }

    func selectedPinboardTitle(selectedPinboard: Pinboard?) -> String {
        selectedPinboard?.name ?? "All"
    }

    func currentPinboardItemCount(
        allItems: [ClipItem],
        selectedPinboardID: UUID?,
        lockStateStore: any PinboardLockStateProviding
    ) -> Int {
        if let selectedPinboardID {
            return allItems.filter { item in
                (item.pinboards?.contains(where: { $0.id == selectedPinboardID }) ?? false)
                    && isItemVisible(item, selectedPinboardID: selectedPinboardID, lockStateStore: lockStateStore)
            }.count
        }

        return allItems.filter { isItemVisible($0, selectedPinboardID: nil, lockStateStore: lockStateStore) }.count
    }

    func isSelectedPinboardAwaitingUnlock(selectedPinboardID: UUID?, lockStateStore: any PinboardLockStateProviding) -> Bool {
        guard let selectedPinboardID else { return false }
        guard lockStateStore.isLocked(selectedPinboardID) else { return false }
        return !lockStateStore.canAccess(selectedPinboardID)
    }

    func advancePinboardSelection(
        by offset: Int,
        container: MartenIOSAppContainer,
        customPinboards: [Pinboard]
    ) {
        guard offset != 0 else { return }

        let pinboardIDs: [UUID?] = [nil] + customPinboards.map(\.id)
        guard pinboardIDs.count > 1 else { return }

        let currentPinboardID = container.selectedPinboardID
        let currentIndex = pinboardIDs.firstIndex(where: { $0 == currentPinboardID }) ?? 0
        let targetIndex = min(max(currentIndex + offset, 0), pinboardIDs.count - 1)
        guard targetIndex != currentIndex else { return }

        swipeDirection = offset
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            container.setSelectedPinboardID(pinboardIDs[targetIndex])
        }
    }

    func reconcilePinboardState(container: MartenIOSAppContainer, customPinboards: [Pinboard]) {
        let allValidIDs = Set(customPinboards.map(\.id))
        let lockableIDs = Set(customPinboards.filter { !$0.isShared }.map(\.id))
        container.lockStateStore.reconcile(validPinboardIDs: lockableIDs)

        if let selectedPinboardID = container.selectedPinboardID,
           !allValidIDs.contains(selectedPinboardID)
        {
            container.setSelectedPinboardID(nil)
        }
    }

    func visibleAllItemsForSearchOptions(container: MartenIOSAppContainer, allItems: [ClipItem]) -> [ClipItem] {
        allItems.filter { isItemVisible($0, selectedPinboardID: nil, lockStateStore: container.lockStateStore) }
    }

    func isItemVisible(
        _ item: ClipItem,
        selectedPinboardID: UUID?,
        lockStateStore: any PinboardLockStateProviding
    ) -> Bool {
        if let selectedPinboardID {
            guard item.pinboards?.contains(where: { $0.id == selectedPinboardID }) ?? false else {
                return false
            }
            return lockStateStore.canAccess(selectedPinboardID)
        }

        let customAssignments = item.pinboards?.filter { !$0.isSystemMarten } ?? []
        guard !customAssignments.isEmpty else { return true }

        return !customAssignments.contains { pinboard in
            !pinboard.isShared && lockStateStore.isLocked(pinboard.id) && !lockStateStore.canAccess(pinboard.id)
        }
    }

    func requestPinboardUnlock(
        _ pinboard: Pinboard,
        lockStateStore: any PinboardLockStateProviding,
        onUnlocked: @MainActor @escaping () -> Void
    ) {
        Task { @MainActor in
            let unlocked = await lockStateStore.unlock(
                pinboardID: pinboard.id,
                pinboardName: pinboard.name
            )
            guard unlocked else { return }
            onUnlocked()
        }
    }

    func handleItemTap(_ item: ClipItem, container: MartenIOSAppContainer) {
        if selectionModel.isSelectionMode {
            selectionModel.toggleSelection(for: item)
            return
        }
        copyItems([item.objectID], container: container)
    }

    func handleItemPreview(_ item: ClipItem, container: MartenIOSAppContainer) {
        searchModel?.donateOpenItem(item)

        switch item.itemTypeValue {
        case .text, .richText:
            activePreviewDestination = .text(item.objectID)
        case .image:
            activePreviewDestination = .image(item.objectID)
        case .code:
            activePreviewDestination = .code(item.objectID)
        case .url:
            activePreviewDestination = .url(item.objectID)
        case .color:
            activePreviewDestination = .color(item.objectID)
        default:
            copyItems([item.objectID], container: container)
        }
    }

    func handleItemEdit(_ item: ClipItem, container: MartenIOSAppContainer) {
        searchModel?.donateOpenItem(item)

        switch item.itemTypeValue {
        case .text, .richText:
            activeEditDestination = .richText(item.objectID)
        case .image:
            activeEditDestination = .image(item.objectID)
        case .code:
            activeEditDestination = .code(item.objectID)
        case .url:
            activeEditDestination = .url(item.objectID)
        case .color:
            activeEditDestination = .color(item.objectID)
        default:
            copyItems([item.objectID], container: container)
        }
    }

    func convertItemType(_ item: ClipItem, to newType: ItemType, container: MartenIOSAppContainer) {
        Task {
            await container.updateItemType(objectID: item.objectID, newType: newType)
            guard container.lastOperationErrorMessage == nil else { return }
            toastController.show(
                "Converted to \(newType.label)",
                systemImage: ItemCardContextAction.conversionTypeSystemImage(newType)
            )
        }
    }

    func transitionFromPreviewToEdit(_ destination: DashboardEditDestination) {
        activePreviewDestination = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.activeEditDestination = destination
        }
    }

    func togglePin(_ item: ClipItem, container: MartenIOSAppContainer) {
        guard container.selectedPinboardID != nil else { return }
        let message = item.isPinned ? "Unpinned" : "Pinned"
        toastController.show(message, systemImage: "pin.fill")
        Task {
            await container.togglePin(objectID: item.objectID)
        }
    }

    func prepareMove(_ objectIDs: [NSManagedObjectID]) {
        guard !objectIDs.isEmpty else { return }
        moveObjectIDs = objectIDs
        isShowingMoveSheet = true
    }

    func prepareDelete(_ objectIDs: [NSManagedObjectID]) {
        guard !objectIDs.isEmpty else { return }
        pendingDeleteObjectIDs = objectIDs
        isShowingDeleteConfirmation = true
    }

    func confirmDelete(container: MartenIOSAppContainer) {
        let pendingIDs = pendingDeleteObjectIDs
        Task {
            await container.deleteItems(pendingIDs)
            selectionModel.clearSelection()
        }
        pendingDeleteObjectIDs = []
    }

    func cancelDelete() {
        pendingDeleteObjectIDs = []
    }

    func copyItemsPlainText(_ objectIDs: [NSManagedObjectID], container: MartenIOSAppContainer) {
        Task { @MainActor in
            let resolver = CoreDataDashboardClipItemResolver(viewContext: container.persistenceController.viewContext)
            let copied = await itemActions.copyItems(
                objectIDs: objectIDs,
                resolver: resolver,
                commandService: container.commandService,
                mode: .plainText
            )
            guard copied != nil else { return }
            let message = objectIDs.count == 1 ? "Copied as plain text" : "Copied \(objectIDs.count) items as plain text"
            toastController.show(message, systemImage: "textformat")
        }
    }

    func copyItems(_ objectIDs: [NSManagedObjectID], container: MartenIOSAppContainer?) {
        guard let container else { return }
        Task { @MainActor in
            let resolver = CoreDataDashboardClipItemResolver(viewContext: container.persistenceController.viewContext)
            let copied = await itemActions.copyItems(
                objectIDs: objectIDs,
                resolver: resolver,
                commandService: container.commandService,
                mode: .bestEffort
            )
            guard copied != nil else { return }
            let message = objectIDs.count == 1 ? "Copied" : "Copied \(objectIDs.count) items"
            toastController.show(message, systemImage: "doc.on.doc.fill")
        }
    }

    func shareItems(_ objectIDs: [NSManagedObjectID], container: MartenIOSAppContainer) {
        let resolver = CoreDataDashboardClipItemResolver(viewContext: container.persistenceController.viewContext)
        let payloads = itemActions.shareItems(objectIDs: objectIDs, resolver: resolver)
        guard !payloads.isEmpty else { return }
        shareSheetContext = DashboardShareSheetContext(items: payloads)
    }

    func reorderItems(_ objectIDs: [NSManagedObjectID], container: MartenIOSAppContainer) {
        Task { @MainActor in
            do {
                try container.clipItemStore.reorderItems(objectIDs: objectIDs)
            } catch {
                container.lastOperationErrorMessage = error.localizedDescription
            }
        }
    }

    func dismissSearch() {
        withAnimation(MartenAnimation.quick) {
            searchModel?.clearSearchText()
            #if os(iOS)
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
            )
            #endif
        }
    }

    func closeSearch() {
        #if os(iOS)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
        #endif
        withAnimation(MartenAnimation.smooth) {
            searchModel?.clearSearchText()
            isSearchExpanded = false
        }
    }
}
