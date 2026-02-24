import SwiftUI

struct WatchLockedPinboardView: View {
    let title: String
    let isAuthenticating: Bool
    let onUnlock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(title) is locked", systemImage: "lock.fill")
                .font(.headline)

            Text("Unlock this pinboard to browse, edit, and move cards.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button(action: onUnlock) {
                HStack(spacing: 6) {
                    if isAuthenticating {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text(isAuthenticating ? "Unlocking" : "Unlock")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAuthenticating)
        }
        .watchCard(prominence: .subtle)
    }
}
