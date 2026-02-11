import MartenCore
import SwiftUI

struct MoveToPinboardSheet: View {
    let pinboards: [Pinboard]
    let lockStateStore: PinboardLockStateStore
    let onSelect: (Pinboard) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(pinboards, id: \.objectID) { pinboard in
                    let isLocked = lockStateStore.isLocked(pinboard.id)
                    Button {
                        onSelect(pinboard)
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color(hex: pinboard.colorHex, fallback: .gray))
                                .frame(width: 10, height: 10)
                            Text(pinboard.name)
                            Spacer()
                            if isLocked {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(isLocked)
                    .accessibilityLabel(isLocked ? "\(pinboard.name), locked" : pinboard.name)
                }
            }
            .navigationTitle("Move To Pinboard")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
