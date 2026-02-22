import MartenCore
import SwiftUI

struct DashboardLockedPinboardView: View {
    let title: String
    let isAuthenticating: Bool
    let onUnlock: () -> Void
    let onSwipe: (Int) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline.weight(.semibold))

            Text("This pinboard is locked.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(action: onUnlock) {
                Label("Unlock", systemImage: "faceid")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAuthenticating)
            .frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    guard abs(horizontal) > abs(vertical) else { return }
                    guard abs(horizontal) >= 55 else { return }
                    onSwipe(horizontal < 0 ? 1 : -1)
                }
        )
        .contentMargins(.top, 120, for: .scrollContent)
    }
}

