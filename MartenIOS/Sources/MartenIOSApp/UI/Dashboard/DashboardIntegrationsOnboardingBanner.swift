import SwiftUI

struct DashboardIntegrationsOnboardingBanner: View {
    let onSetup: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        MartenGlassSurface(cornerRadius: 14, padding: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Integrations")
                        .font(.subheadline.weight(.semibold))
                    Text("Share Extension, Keyboard, Widgets & Siri")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button("Setup", action: onSetup)
                    .font(.caption.weight(.bold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
    }
}

