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
            ZStack {
                // Background
                if #available(iOS 26, *) {
                    Color.clear.ignoresSafeArea()
                } else {
                Color(platformColor: .platformSystemGroupedBackground)
                        .ignoresSafeArea()
                }

                ScrollView {
                    VStack(spacing: 8) {
                        allDestinationRow

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
                                MartenGlassSurface(cornerRadius: 14, padding: 0, isInteractive: true) {
                                    HStack(spacing: 12) {
                                        // Color + sign indicator
                                        ZStack {
                                            Circle()
                                                .fill(Color(hex: pinboard.colorHex, fallback: .gray))
                                                .frame(width: 32, height: 32)
                                                .shadow(color: Color(hex: pinboard.colorHex, fallback: .gray).opacity(0.4), radius: 3, x: 0, y: 1)

                                            if let iconName = pinboard.iconName, !iconName.isEmpty {
                                                if PinboardSignCatalogIOS.isSystemSymbol(iconName) {
                                                    Image(systemName: iconName)
                                                        .font(.system(size: 13, weight: .bold))
                                                        .foregroundStyle(.white)
                                                } else {
                                                    Text(iconName)
                                                        .font(.system(size: 16))
                                                }
                                            }
                                        }

                                        Text(pinboard.name)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)

                                        Spacer()

                                        if isLocked {
                                            Image(systemName: canAccess ? "lock.open.fill" : "lock.fill")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .contentShape(Rectangle())
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                isLocked && !canAccess ? "\(pinboard.name), locked" : pinboard.name
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
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
            MartenGlassSurface(cornerRadius: 14, padding: 0, isInteractive: true) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(.quaternary)
                            .frame(width: 32, height: 32)

                        Image(systemName: "square.stack")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.secondary)
                    }

                    Text("All")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("All")
    }
}
