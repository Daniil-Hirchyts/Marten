import MartenCore
import SwiftUI

struct ItemCardGridView: View {
    let items: [ClipItem]
    let selectionModel: DashboardSelectionModel
    let onTapItem: (ClipItem) -> Void
    let onCopyItem: (ClipItem) -> Void
    let onShareItem: (ClipItem) -> Void
    let onMoveItem: (ClipItem) -> Void
    let onDeleteItem: (ClipItem) -> Void

    private let columns = [
        GridItem(.flexible(minimum: 160, maximum: 500), spacing: 12, alignment: .top),
        GridItem(.flexible(minimum: 160, maximum: 500), spacing: 12, alignment: .top),
    ]

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView(
                "No Items Yet",
                systemImage: "tray",
                description: Text("Use Quick Add to create your first item.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(items, id: \.objectID) { item in
                        ItemCardView(
                            item: item,
                            isSelectionMode: selectionModel.isSelectionMode,
                            isSelected: selectionModel.isSelected(item),
                            dragPayload: selectionModel.dragPayload(for: item),
                            onTap: {
                                onTapItem(item)
                            },
                            onCopy: {
                                onCopyItem(item)
                            },
                            onShare: {
                                onShareItem(item)
                            },
                            onMove: {
                                onMoveItem(item)
                            },
                            onDelete: {
                                onDeleteItem(item)
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
        }
    }
}
