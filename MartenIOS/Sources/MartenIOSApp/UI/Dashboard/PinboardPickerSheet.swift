import CoreData
import MartenCore
import SwiftUI

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

                ForEach(orderedPinboards, id: \.objectID) { pinboard in
                    pinboardRow(pinboard)
                        .contentShape(.dragPreview, RoundedRectangle(cornerRadius: rowCornerRadius))
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                onDelete(pinboard)
                            } label: {
                                MartenSwipeActionIcon(systemName: "trash", backgroundColor: .red, label: "Delete")
                            }
                            .tint(.red)
                            .accessibilityLabel("Delete")
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            let supportsLock = !pinboard.isShared
                            let isLocked = supportsLock && lockStateStore.isLocked(pinboard.id)
                            let canAccess = !isLocked || lockStateStore.canAccess(pinboard.id)

                            Button {
                                onEdit(pinboard)
                            } label: {
                                MartenSwipeActionIcon(systemName: "pencil", backgroundColor: .blue, label: "Edit")
                            }
                            .tint(.blue)
                            .accessibilityLabel("Edit")

                            if container.sharingRepository != nil && (pinboard.isShared || !isLocked) {
                                Button {
                                    guard container.canOpenShareSettings(for: pinboard) else { return }
                                    onShare(pinboard)
                                } label: {
                                    MartenSwipeActionIcon(
                                        systemName: "square.and.arrow.up",
                                        backgroundColor: .green,
                                        label: "Share"
                                    )
                                }
                                .tint(.green)
                                .accessibilityLabel("Share")
                            }

                            if supportsLock {
                                if isLocked {
                                    if canAccess {
                                        Button {
                                            container.lockPinboardNow(pinboard)
                                        } label: {
                                            MartenSwipeActionIcon(systemName: "lock.fill", backgroundColor: .orange, label: "Lock")
                                        }
                                        .tint(.orange)
                                        .accessibilityLabel("Lock")
                                    }

                                    Button {
                                        container.setPinboardLock(false, for: pinboard)
                                    } label: {
                                        MartenSwipeActionIcon(systemName: "lock.slash", backgroundColor: .gray, label: "Disable")
                                    }
                                    .tint(.gray)
                                    .accessibilityLabel("Disable Lock")
                                } else {
                                    Button {
                                        container.setPinboardLock(true, for: pinboard)
                                    } label: {
                                        MartenSwipeActionIcon(systemName: "lock", backgroundColor: .orange, label: "Lock")
                                    }
                                    .tint(.orange)
                                    .accessibilityLabel("Lock")
                                }
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
        let supportsLock = !pinboard.isShared
        let isLocked = supportsLock && lockStateStore.isLocked(pinboard.id)
        let canAccess = !isLocked || lockStateStore.canAccess(pinboard.id)

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
