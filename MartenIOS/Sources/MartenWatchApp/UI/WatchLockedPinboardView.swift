import SwiftUI

struct WatchLockedPinboardView: View {
    let title: String
    let isAuthenticating: Bool
    let onUnlock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(title) is locked", systemImage: "lock.fill")
                .font(.headline)

            Button(action: onUnlock) {
                Text("Unlock")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .watchCard(prominence: .subtle)
        // Also trigger unlock on tap
        .contentShape(.rect)
        .onTapGesture {
            onUnlock()
        }
    }
}
