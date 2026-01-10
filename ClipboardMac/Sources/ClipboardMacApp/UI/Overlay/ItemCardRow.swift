import ClipboardCore
import SwiftUI

struct ItemCardRow: View {
    let items: [ClipItem]
    let pinboards: [Pinboard]
    let onCopy: (ClipItem) -> Void
    let onDelete: (ClipItem) -> Void
    let onTogglePin: (ClipItem) -> Void
    let onMoveToPinboard: (ClipItem, Pinboard) -> Void
    let onCreatePinboard: (ClipItem) -> Void

    var body: some View {
        if #available(macOS 14.0, *) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    cardViews
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    cardViews
                }
            }
        }
    }

    @ViewBuilder
    private var cardViews: some View {
        ForEach(items) { item in
            ItemCard(
                item: item,
                pinboards: pinboards,
                onCopy: { onCopy(item) },
                onDelete: { onDelete(item) },
                onTogglePin: { onTogglePin(item) },
                onMoveToPinboard: { onMoveToPinboard(item, $0) },
                onCreatePinboard: { onCreatePinboard(item) }
            )
            .frame(width: 280)
        }
    }
}
