import CoreData
import MartenCore
import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit

@MainActor
final class ItemCardCollectionViewController: UIViewController {
    private enum Section {
        case main
    }

    private enum PanSelectionAction {
        case select
        case deselect
    }

    private let selectionModel: DashboardSelectionModel
    private let onTapItem: (ClipItem) -> Void
    private let onCopyItem: (ClipItem) -> Void
    private let onCopyPlainTextItem: (ClipItem) -> Void
    private let onPreviewItem: (ClipItem) -> Void
    private let onTogglePinItem: (ClipItem) -> Void
    private let onShareItem: (ClipItem) -> Void
    private let onMoveItem: (ClipItem) -> Void
    private let onDeleteItem: (ClipItem) -> Void
    private let onReorderItems: ([NSManagedObjectID]) -> Void
    private let onSwipeToNextPinboard: () -> Void
    private let onSwipeToPreviousPinboard: () -> Void

    private let dragPayloadBuilder = ItemCardDragPayloadBuilder()

    private var itemsByID: [NSManagedObjectID: ClipItem] = [:]
    private var orderedIDs: [NSManagedObjectID] = []
    private var canReorder = false
    private var allowPinning = false
    private var isSelectionMode = false
    private var selectedObjectIDs: Set<NSManagedObjectID> = []
    private var lastLayoutColumnCount: Int = 0
    private var isReorderingInProgress = false
    private var lastSnapshotIDs: [NSManagedObjectID] = []

    private lazy var selectionPanGesture: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handleSelectionPan(_:)))
        recognizer.minimumNumberOfTouches = 1
        recognizer.maximumNumberOfTouches = 1
        recognizer.cancelsTouchesInView = true
        recognizer.delegate = self
        return recognizer
    }()

    private lazy var swipeLeftGesture: UISwipeGestureRecognizer = {
        let recognizer = UISwipeGestureRecognizer(
            target: self,
            action: #selector(handleSwipeLeft(_:))
        )
        recognizer.direction = .left
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        return recognizer
    }()

    private lazy var swipeRightGesture: UISwipeGestureRecognizer = {
        let recognizer = UISwipeGestureRecognizer(
            target: self,
            action: #selector(handleSwipeRight(_:))
        )
        recognizer.direction = .right
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        return recognizer
    }()

    private var panSelectionAction: PanSelectionAction?
    private var panVisitedObjectIDs: Set<NSManagedObjectID> = []
    private var wasScrollEnabledBeforePan = true

    private lazy var flowLayout: UICollectionViewFlowLayout = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        layout.estimatedItemSize = .zero
        return layout
    }()

    private lazy var collectionView: UICollectionView = {
        let view = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        view.backgroundColor = .clear
        view.alwaysBounceVertical = true
        view.allowsMultipleSelection = true
        view.allowsMultipleSelectionDuringEditing = true
        view.dragInteractionEnabled = true
        view.delegate = self
        view.dragDelegate = self
        view.dropDelegate = self
        return view
    }()

    private lazy var dataSource: UICollectionViewDiffableDataSource<Section, NSManagedObjectID> = {
        let registration = UICollectionView.CellRegistration<UICollectionViewCell, NSManagedObjectID> { [weak self] cell, _, objectID in
            guard let self else { return }
            guard let item = self.itemsByID[objectID] else {
                cell.contentConfiguration = nil
                return
            }

            cell.contentConfiguration = UIHostingConfiguration {
                ItemCardView(
                    item: item,
                    isSelectionMode: self.isSelectionMode,
                    isSelected: self.selectedObjectIDs.contains(item.objectID),
                    handlesTapGesture: false,
                    handlesPressGesture: false,
                    showsContextMenu: false,
                    showsSelectionFeedback: false,
                    allowPinning: self.allowPinning,
                    onTap: {},
                    onCopy: { self.onCopyItem(item) },
                    onCopyPlainText: { self.onCopyPlainTextItem(item) },
                    onPreview: { self.onPreviewItem(item) },
                    onShare: { self.onShareItem(item) },
                    onMove: { self.onMoveItem(item) },
                    onDelete: { self.onDeleteItem(item) }
                )
                .allowsHitTesting(false)
            }
            .margins(.all, 0)
        }

        return UICollectionViewDiffableDataSource(collectionView: collectionView) {
            collectionView, indexPath, objectID in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: objectID)
        }
    }()

    init(
        selectionModel: DashboardSelectionModel,
        onTapItem: @escaping (ClipItem) -> Void,
        onCopyItem: @escaping (ClipItem) -> Void,
        onCopyPlainTextItem: @escaping (ClipItem) -> Void,
        onPreviewItem: @escaping (ClipItem) -> Void,
        onTogglePinItem: @escaping (ClipItem) -> Void,
        onShareItem: @escaping (ClipItem) -> Void,
        onMoveItem: @escaping (ClipItem) -> Void,
        onDeleteItem: @escaping (ClipItem) -> Void,
        onReorderItems: @escaping ([NSManagedObjectID]) -> Void,
        onSwipeToNextPinboard: @escaping () -> Void,
        onSwipeToPreviousPinboard: @escaping () -> Void
    ) {
        self.selectionModel = selectionModel
        self.onTapItem = onTapItem
        self.onCopyItem = onCopyItem
        self.onCopyPlainTextItem = onCopyPlainTextItem
        self.onPreviewItem = onPreviewItem
        self.onTogglePinItem = onTogglePinItem
        self.onShareItem = onShareItem
        self.onMoveItem = onMoveItem
        self.onDeleteItem = onDeleteItem
        self.onReorderItems = onReorderItems
        self.onSwipeToNextPinboard = onSwipeToNextPinboard
        self.onSwipeToPreviousPinboard = onSwipeToPreviousPinboard
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = collectionView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.addGestureRecognizer(selectionPanGesture)
        collectionView.addGestureRecognizer(swipeLeftGesture)
        collectionView.addGestureRecognizer(swipeRightGesture)
        collectionView.panGestureRecognizer.require(toFail: selectionPanGesture)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLayoutIfNeeded()
    }

    func update(
        items: [ClipItem],
        canReorder: Bool,
        allowPinning: Bool,
        isSelectionMode: Bool,
        selectedObjectIDs: Set<NSManagedObjectID>,
        contentInsets: UIEdgeInsets
    ) {
        let previousIsSelectionMode = self.isSelectionMode
        let previousSelectedIDs = self.selectedObjectIDs

        self.canReorder = canReorder
        self.allowPinning = allowPinning
        self.isSelectionMode = isSelectionMode
        self.selectedObjectIDs = selectedObjectIDs
        self.collectionView.contentInset = contentInsets
        self.collectionView.verticalScrollIndicatorInsets = contentInsets

        itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.objectID, $0) })

        let incomingIDs = items.map(\.objectID)
        var needsSnapshotApply = false

        if Set(orderedIDs) != Set(incomingIDs) {
            orderedIDs = incomingIDs
            isReorderingInProgress = false
            needsSnapshotApply = true
        } else if !isReorderingInProgress, orderedIDs != incomingIDs {
            orderedIDs = incomingIDs
            needsSnapshotApply = true
        }

        if needsSnapshotApply || lastSnapshotIDs != orderedIDs {
            applySnapshot(animated: needsSnapshotApply)
        } else {
            if previousIsSelectionMode != isSelectionMode {
                reconfigureItems(orderedIDs)
            }

            let changedSelectionIDs = previousSelectedIDs.symmetricDifference(selectedObjectIDs)
            if !changedSelectionIDs.isEmpty {
                reconfigureItems(Array(changedSelectionIDs))
            }
        }

        synchronizeSelectionToCollectionView()
        updateLayoutIfNeeded()

        selectionPanGesture.isEnabled = isSelectionMode
        let isPinboardSwipeEnabled = !isSelectionMode
        swipeLeftGesture.isEnabled = isPinboardSwipeEnabled
        swipeRightGesture.isEnabled = isPinboardSwipeEnabled
    }

    private func applySnapshot(animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, NSManagedObjectID>()
        snapshot.appendSections([.main])
        snapshot.appendItems(orderedIDs, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: animated)
        lastSnapshotIDs = orderedIDs
    }

    private func reconfigureItems(_ ids: [NSManagedObjectID]) {
        var snapshot = dataSource.snapshot()
        let reconfigurable = ids.filter { snapshot.indexOfItem($0) != nil }
        guard !reconfigurable.isEmpty else { return }
        snapshot.reconfigureItems(reconfigurable)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func synchronizeSelectionToCollectionView() {
        guard isSelectionMode else {
            for indexPath in collectionView.indexPathsForSelectedItems ?? [] {
                collectionView.deselectItem(at: indexPath, animated: false)
            }
            return
        }

        let idsInSnapshot = Set(orderedIDs)
        let desiredSelection = selectedObjectIDs.intersection(idsInSnapshot)

        for indexPath in collectionView.indexPathsForSelectedItems ?? [] {
            guard let id = dataSource.itemIdentifier(for: indexPath) else { continue }
            if !desiredSelection.contains(id) {
                collectionView.deselectItem(at: indexPath, animated: false)
            }
        }

        for (index, id) in orderedIDs.enumerated() {
            guard desiredSelection.contains(id) else { continue }
            let indexPath = IndexPath(item: index, section: 0)
            if collectionView.cellForItem(at: indexPath) != nil {
                collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
            }
        }
    }

    private func updateLayoutIfNeeded() {
        let desiredColumns = ItemCardLayoutCalculator.columnCount(for: traitCollection)

        let availableWidth = collectionView.bounds.width
            - collectionView.adjustedContentInset.left
            - collectionView.adjustedContentInset.right
            - flowLayout.sectionInset.left
            - flowLayout.sectionInset.right

        let itemWidth = ItemCardLayoutCalculator.itemWidth(
            containerWidth: availableWidth,
            columns: desiredColumns,
            spacing: flowLayout.minimumInteritemSpacing
        )

        guard desiredColumns != lastLayoutColumnCount || flowLayout.itemSize.width != itemWidth else { return }

        lastLayoutColumnCount = desiredColumns
        flowLayout.itemSize = CGSize(width: itemWidth, height: itemWidth)
        flowLayout.invalidateLayout()
    }

    @objc
    private func handleSelectionPan(_ recognizer: UIPanGestureRecognizer) {
        guard isSelectionMode else { return }
        guard !collectionView.hasActiveDrag else { return }

        let location = recognizer.location(in: collectionView)

        switch recognizer.state {
        case .began:
            guard let indexPath = collectionView.indexPathForItem(at: location),
                  let objectID = dataSource.itemIdentifier(for: indexPath) else {
                panSelectionAction = nil
                return
            }

            wasScrollEnabledBeforePan = collectionView.isScrollEnabled
            collectionView.isScrollEnabled = false

            panVisitedObjectIDs.removeAll(keepingCapacity: true)
            panSelectionAction = selectedObjectIDs.contains(objectID) ? .deselect : .select
            applyPanSelection(to: objectID, at: indexPath)

        case .changed:
            guard let indexPath = collectionView.indexPathForItem(at: location),
                  let objectID = dataSource.itemIdentifier(for: indexPath) else {
                return
            }

            applyPanSelection(to: objectID, at: indexPath)

        case .ended, .cancelled, .failed:
            collectionView.isScrollEnabled = wasScrollEnabledBeforePan
            wasScrollEnabledBeforePan = true

            panSelectionAction = nil
            panVisitedObjectIDs.removeAll(keepingCapacity: true)

            selectionModel.selectedObjectIDs = selectedObjectIDs

        default:
            break
        }
    }

    @objc
    private func handleSwipeLeft(_ recognizer: UISwipeGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        guard !isSelectionMode else { return }
        guard !collectionView.hasActiveDrag else { return }
        onSwipeToNextPinboard()
    }

    @objc
    private func handleSwipeRight(_ recognizer: UISwipeGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        guard !isSelectionMode else { return }
        guard !collectionView.hasActiveDrag else { return }
        onSwipeToPreviousPinboard()
    }

    private func applyPanSelection(to objectID: NSManagedObjectID, at indexPath: IndexPath) {
        guard let action = panSelectionAction else { return }
        guard !panVisitedObjectIDs.contains(objectID) else { return }

        panVisitedObjectIDs.insert(objectID)

        switch action {
        case .select:
            guard !selectedObjectIDs.contains(objectID) else { return }
            selectedObjectIDs.insert(objectID)
            collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
            reconfigureItems([objectID])

        case .deselect:
            guard selectedObjectIDs.contains(objectID) else { return }
            selectedObjectIDs.remove(objectID)
            collectionView.deselectItem(at: indexPath, animated: false)
            reconfigureItems([objectID])
        }
    }
}

extension ItemCardCollectionViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        if collectionView.hasActiveDrag {
            return false
        }
        return true
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let objectID = dataSource.itemIdentifier(for: indexPath),
              let item = itemsByID[objectID] else {
            return
        }

        if isSelectionMode {
            selectedObjectIDs.insert(objectID)
            selectionModel.selectedObjectIDs = selectedObjectIDs
            reconfigureItems([objectID])
            return
        }

        onTapItem(item)
        collectionView.deselectItem(at: indexPath, animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard let objectID = dataSource.itemIdentifier(for: indexPath) else { return }
        guard isSelectionMode else { return }

        selectedObjectIDs.remove(objectID)
        selectionModel.selectedObjectIDs = selectedObjectIDs
        reconfigureItems([objectID])
    }

    func collectionView(_ collectionView: UICollectionView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        isSelectionMode
    }

    func collectionView(_ collectionView: UICollectionView, didBeginMultipleSelectionInteractionAt indexPath: IndexPath) {
    }

    func collectionViewDidEndMultipleSelectionInteraction(_ collectionView: UICollectionView) {
        selectionModel.selectedObjectIDs = selectedObjectIDs
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard !isSelectionMode else { return nil }
        guard let objectID = dataSource.itemIdentifier(for: indexPath),
              let item = itemsByID[objectID] else {
            return nil
        }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            let actions = ItemCardContextAction.ordered(allowPinning: self.allowPinning).map {
                self.menuAction(for: $0, item: item)
            }
            return UIMenu(children: actions)
        }
    }

    private func menuAction(for action: ItemCardContextAction, item: ClipItem) -> UIAction {
        let attributes: UIMenuElement.Attributes = action.isDestructive ? [.destructive] : []

        if action == .togglePin {
            return UIAction(
                title: item.isPinned ? "Unpin" : "Pin",
                image: UIImage(systemName: item.isPinned ? "pin.slash" : "pin")
            ) { [weak self] _ in
                guard let self else { return }
                self.onTogglePinItem(item)
            }
        }

        return UIAction(
            title: action.title,
            image: UIImage(systemName: action.systemImage),
            attributes: attributes
        ) { [weak self] _ in
            guard let self else { return }
            switch action {
            case .copy:
                self.onCopyItem(item)
            case .copyPlainText:
                self.onCopyPlainTextItem(item)
            case .preview:
                self.onPreviewItem(item)
            case .togglePin:
                self.onTogglePinItem(item)
            case .share:
                self.onShareItem(item)
            case .moveToPinboard:
                self.onMoveItem(item)
            case .delete:
                self.onDeleteItem(item)
            }
        }
    }
}

extension ItemCardCollectionViewController: UICollectionViewDragDelegate {
    func collectionView(_ collectionView: UICollectionView, dragSessionWillBegin session: UIDragSession) {
        isReorderingInProgress = canReorder && !isSelectionMode
    }

    func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: UIDragSession) {
        isReorderingInProgress = false
    }

    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard let objectID = dataSource.itemIdentifier(for: indexPath),
              let item = itemsByID[objectID] else {
            return []
        }

        let dragSet = NSMutableSet()
        session.localContext = dragSet

        // Only return the single touched item here. UICollectionView auto-lifts
        // other selected cells and calls itemsForAddingTo for each, so returning
        // all selected items here would double-count them.
        let objectIDKey = objectID.uriRepresentation().absoluteString as NSString
        dragSet.add(objectIDKey)
        return [dragPayloadBuilder.dragItem(for: objectID, item: item)]
    }

    func collectionView(_ collectionView: UICollectionView, itemsForAddingTo session: UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] {
        guard isSelectionMode || !canReorder else { return [] }
        guard let dragSet = session.localContext as? NSMutableSet else { return [] }
        guard let objectID = dataSource.itemIdentifier(for: indexPath),
              let item = itemsByID[objectID] else {
            return []
        }

        let objectIDKey = objectID.uriRepresentation().absoluteString as NSString
        guard !dragSet.contains(objectIDKey) else { return [] }

        dragSet.add(objectIDKey)
        return [dragPayloadBuilder.dragItem(for: objectID, item: item)]
    }
}

extension ItemCardCollectionViewController: UICollectionViewDropDelegate {
    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        guard canReorder, !isSelectionMode else {
            return UICollectionViewDropProposal(operation: .forbidden)
        }

        if session.localDragSession != nil {
            return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
        }

        return UICollectionViewDropProposal(operation: .copy)
    }

    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard canReorder, !isSelectionMode else { return }
        guard let destinationIndexPath = coordinator.destinationIndexPath else { return }

        let destinationIndex = min(max(destinationIndexPath.item, 0), orderedIDs.count)

        let proposedObjectIDsToMove: [NSManagedObjectID] = coordinator.items.compactMap { dropItem in
            dropItem.dragItem.localObject as? NSManagedObjectID
        }

        guard !proposedObjectIDsToMove.isEmpty else { return }

        let indexByID = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { ($0.element, $0.offset) })
        let objectIDsToMove = proposedObjectIDsToMove.sorted {
            (indexByID[$0] ?? 0) < (indexByID[$1] ?? 0)
        }

        let movingSet = Set(objectIDsToMove)
        let remaining = orderedIDs.filter { !movingSet.contains($0) }
        let insertionIndex = min(destinationIndex, remaining.count)
        orderedIDs = Array(remaining.prefix(insertionIndex)) + objectIDsToMove + Array(remaining.dropFirst(insertionIndex))

        applySnapshot(animated: true)
        onReorderItems(orderedIDs)
    }
}

extension ItemCardCollectionViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === selectionPanGesture {
            guard isSelectionMode else { return false }
            guard !collectionView.hasActiveDrag else { return false }

            let location = gestureRecognizer.location(in: collectionView)
            return collectionView.indexPathForItem(at: location) != nil
        }

        if gestureRecognizer === swipeLeftGesture || gestureRecognizer === swipeRightGesture {
            return !isSelectionMode && !collectionView.hasActiveDrag
        }

        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === swipeLeftGesture
            || gestureRecognizer === swipeRightGesture
            || otherGestureRecognizer === swipeLeftGesture
            || otherGestureRecognizer === swipeRightGesture
        {
            return true
        }

        return false
    }
}

#endif
