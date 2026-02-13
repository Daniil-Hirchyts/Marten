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

    private let selectionModel: DashboardSelectionModel
    private let onTapItem: (ClipItem) -> Void
    private let onCopyItem: (ClipItem) -> Void
    private let onCopyPlainTextItem: (ClipItem) -> Void
    private let onPreviewItem: (ClipItem) -> Void
    private let onShareItem: (ClipItem) -> Void
    private let onMoveItem: (ClipItem) -> Void
    private let onDeleteItem: (ClipItem) -> Void
    private let onReorderItems: ([NSManagedObjectID]) -> Void

    private var itemsByID: [NSManagedObjectID: ClipItem] = [:]
    private var orderedIDs: [NSManagedObjectID] = []
    private var canReorder = false
    private var isSelectionMode = false
    private var selectedObjectIDs: Set<NSManagedObjectID> = []
    private var lastLayoutColumnCount: Int = 0
    private var isReorderingInProgress = false
    private var lastSnapshotIDs: [NSManagedObjectID] = []

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
                    onTap: {},
                    onCopy: { self.onCopyItem(item) },
                    onCopyPlainText: { self.onCopyPlainTextItem(item) },
                    onPreview: { self.onPreviewItem(item) },
                    onShare: { self.onShareItem(item) },
                    onMove: { self.onMoveItem(item) },
                    onDelete: { self.onDeleteItem(item) }
                )
                .allowsHitTesting(!self.isSelectionMode)
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
        onShareItem: @escaping (ClipItem) -> Void,
        onMoveItem: @escaping (ClipItem) -> Void,
        onDeleteItem: @escaping (ClipItem) -> Void,
        onReorderItems: @escaping ([NSManagedObjectID]) -> Void
    ) {
        self.selectionModel = selectionModel
        self.onTapItem = onTapItem
        self.onCopyItem = onCopyItem
        self.onCopyPlainTextItem = onCopyPlainTextItem
        self.onPreviewItem = onPreviewItem
        self.onShareItem = onShareItem
        self.onMoveItem = onMoveItem
        self.onDeleteItem = onDeleteItem
        self.onReorderItems = onReorderItems
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = collectionView
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLayoutIfNeeded()
    }

    func update(
        items: [ClipItem],
        canReorder: Bool,
        isSelectionMode: Bool,
        selectedObjectIDs: Set<NSManagedObjectID>,
        contentInsets: UIEdgeInsets
    ) {
        let previousIsSelectionMode = self.isSelectionMode
        let previousSelectedIDs = self.selectedObjectIDs

        self.canReorder = canReorder
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
        let desiredColumns = traitCollection.horizontalSizeClass == .regular ? 3 : 2

        let availableWidth = collectionView.bounds.width
            - collectionView.adjustedContentInset.left
            - collectionView.adjustedContentInset.right
            - flowLayout.sectionInset.left
            - flowLayout.sectionInset.right

        let spacing = flowLayout.minimumInteritemSpacing
        let rawItemWidth = (availableWidth - spacing * CGFloat(desiredColumns - 1)) / CGFloat(desiredColumns)
        let itemWidth = floor(max(150, min(500, rawItemWidth)))

        guard desiredColumns != lastLayoutColumnCount || flowLayout.itemSize.width != itemWidth else { return }

        lastLayoutColumnCount = desiredColumns
        flowLayout.itemSize = CGSize(width: itemWidth, height: itemWidth)
        flowLayout.invalidateLayout()
    }
}

#endif

extension ItemCardCollectionViewController: UICollectionViewDelegate {
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
              itemsByID[objectID] != nil else {
            return []
        }

        let dragSet = NSMutableSet()
        session.localContext = dragSet

        let objectIDsToDrag: [NSManagedObjectID]
        if isSelectionMode, selectedObjectIDs.contains(objectID), !selectedObjectIDs.isEmpty {
            objectIDsToDrag = Array(selectedObjectIDs)
        } else {
            objectIDsToDrag = [objectID]
        }

        objectIDsToDrag.forEach { dragSet.add($0) }
        return objectIDsToDrag.map { makeDragItem(for: $0) }
    }

    func collectionView(_ collectionView: UICollectionView, itemsForAddingTo session: UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] {
        guard isSelectionMode || !canReorder else { return [] }
        guard let dragSet = session.localContext as? NSMutableSet else { return [] }
        guard let objectID = dataSource.itemIdentifier(for: indexPath),
              itemsByID[objectID] != nil else {
            return []
        }

        if dragSet.contains(objectID) {
            return []
        }

        dragSet.add(objectID)
        return [makeDragItem(for: objectID)]
    }

    private func makeDragItem(for objectID: NSManagedObjectID) -> UIDragItem {
        let payload = ItemDragPayload(objectIDs: [objectID])
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.martenItemDragPayload.identifier, visibility: .all) { completion in
            do {
                let data = try JSONEncoder().encode(payload)
                completion(data, nil)
            } catch {
                completion(nil, error)
            }
            return nil
        }

        let dragItem = UIDragItem(itemProvider: provider)
        dragItem.localObject = objectID
        return dragItem
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
