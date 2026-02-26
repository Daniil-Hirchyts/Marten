import MartenCore
import SwiftUI

extension ItemCard {
    @ViewBuilder
    var contextMenuContent: some View {
        CardContextMenu(
            item: item,
            itemID: item.id,
            isPinned: item.isPinned,
            allowPinning: allowPinning,
            readOnly: readOnly,
            assignedPinboardIDs: assignedPinboardIDs,
            pinboards: pinboards,
            lockedPinboardIDs: lockedPinboardIDs,
            onPaste: onPaste,
            onPastePlainText: onPastePlainText,
            onTogglePin: onTogglePin,
            onCopy: onCopy,
            onConvertType: onConvertType,
            onMoveToPinboard: onMoveToPinboard,
            onCreatePinboard: onCreatePinboard,
            onEdit: onEdit,
            onRename: onRename,
            onDelete: onDelete
        )
    }
}
