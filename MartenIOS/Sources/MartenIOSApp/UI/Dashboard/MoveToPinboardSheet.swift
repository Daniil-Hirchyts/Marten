import MartenCore
import SwiftUI

struct MoveToPinboardSheet: View {
    enum Destination {
        case all
        case pinboard(Pinboard)
    }

    let pinboards: [Pinboard]
    let lockStateStore: PinboardLockStateStore
    let onSelect: (Destination) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private let rowCornerRadius: CGFloat = 999

    private var filteredPinboards: [Pinboard] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return pinboards
        }
        return pinboards.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                allDestinationRow
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                ForEach(filteredPinboards, id: \.objectID) { pinboard in
                    let isLocked = lockStateStore.isLocked(pinboard.id)
                    let canAccess = lockStateStore.canAccess(pinboard.id)

                    Button {
                        if isLocked && !canAccess {
                            Task { @MainActor in
                                let unlocked = await lockStateStore.unlock(
                                    pinboardID: pinboard.id,
                                    pinboardName: pinboard.name
                                )
                                guard unlocked else { return }
                                onSelect(.pinboard(pinboard))
                                dismiss()
                            }
                        } else {
                            onSelect(.pinboard(pinboard))
                            dismiss()
                        }
                    } label: {
                        PinboardSelectionRow(
                            leading: .pinboard(
                                colorHex: pinboard.colorHex, sign: pinboard.iconName),
                            title: pinboard.name,
                            showsSharedBadge: pinboard.isShared,
                            lockState: .init(isLocked: isLocked, canAccess: canAccess),
                            cornerRadius: rowCornerRadius
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        isLocked && !canAccess ? "\(pinboard.name), locked" : pinboard.name
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(platformColor: .platformSystemGroupedBackground))
            .searchable(text: $searchText, prompt: "Find pinboard")
            .navigationTitle("Move To")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var allDestinationRow: some View {
        Button {
            onSelect(.all)
            dismiss()
        } label: {
            PinboardSelectionRow(leading: .all, title: "All", cornerRadius: rowCornerRadius)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("All")
    }
}
