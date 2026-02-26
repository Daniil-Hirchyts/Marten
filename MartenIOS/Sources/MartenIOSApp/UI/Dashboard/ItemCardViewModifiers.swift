import MartenCore
import SwiftUI

struct PressGestureModifier: ViewModifier {
    let isEnabled: Bool
    @Binding var isPressed: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.onLongPressGesture(minimumDuration: .infinity, perform: {}, onPressingChanged: { pressing in
                isPressed = pressing
            })
        } else {
            content
        }
    }
}

struct SelectionFeedbackModifier: ViewModifier {
    let isEnabled: Bool
    let isSelected: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.sensoryFeedback(.selection, trigger: isSelected)
        } else {
            content
        }
    }
}

struct ContextMenuModifier: ViewModifier {
    let isEnabled: Bool
    let allowPinning: Bool
    let currentItemType: ItemType
    let sourceText: String?
    let isPinned: Bool
    let onCopy: () -> Void
    let onCopyPlainText: () -> Void
    let onPreview: () -> Void
    let onEdit: () -> Void
    let onConvertType: (ItemType) -> Void
    let onTogglePin: () -> Void
    let onShare: () -> Void
    let onMove: () -> Void
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.contextMenu {
                ForEach(ItemCardContextAction.ordered(allowPinning: allowPinning), id: \.self) { action in
                    button(for: action)
                    if showsDivider(after: action) {
                        Divider()
                    }
                }
            }
        } else {
            content
        }
    }

    @ViewBuilder
    private func button(for action: ItemCardContextAction) -> some View {
        if action == .togglePin {
            Button { perform(action) } label: {
                Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
            }
        } else if action == .convertType {
            let conversionTargets = ItemCardContextAction.conversionTargets(
                for: currentItemType,
                sourceText: sourceText
            )
            if !conversionTargets.isEmpty {
                Menu {
                    ForEach(conversionTargets, id: \.self) { type in
                        Button {
                            onConvertType(type)
                        } label: {
                            Label(type.label, systemImage: ItemCardContextAction.conversionTypeSystemImage(type))
                        }
                    }
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                }
            }
        } else if action.isDestructive {
            Button(role: .destructive) { perform(action) } label: {
                Label(action.title, systemImage: action.systemImage)
            }
        } else {
            Button { perform(action) } label: {
                Label(action.title, systemImage: action.systemImage)
            }
        }
    }

    private func perform(_ action: ItemCardContextAction) {
        switch action {
        case .copy:
            onCopy()
        case .copyPlainText:
            onCopyPlainText()
        case .preview:
            onPreview()
        case .edit:
            onEdit()
        case .convertType:
            break
        case .togglePin:
            onTogglePin()
        case .share:
            onShare()
        case .moveToPinboard:
            onMove()
        case .delete:
            onDelete()
        }
    }

    private func showsDivider(after action: ItemCardContextAction) -> Bool {
        action == .copyPlainText || action == .togglePin || action == .moveToPinboard
    }
}
