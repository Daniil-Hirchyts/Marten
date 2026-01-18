import SwiftUI

struct SubscriptionSettingsContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Current Plan Section
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeader("Current Plan", icon: "star")

                SettingsCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [.blue, .purple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 48, height: 48)

                                Image(systemName: "sparkles")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.white)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Free Plan")
                                    .font(.system(size: 15, weight: .semibold))
                                Text("Basic clipboard history")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                    }
                }
            }

            // Features Section
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeader("Pro Features", icon: "crown")

                SettingsCard {
                    VStack(alignment: .leading, spacing: 14) {
                        FeatureRow(
                            icon: "infinity",
                            title: "Unlimited History",
                            description: "Never lose a clipboard item"
                        )

                        Divider()
                            .background(Color.white.opacity(0.1))

                        FeatureRow(
                            icon: "icloud.fill",
                            title: "iCloud Sync",
                            description: "Sync across all your devices"
                        )

                        Divider()
                            .background(Color.white.opacity(0.1))

                        FeatureRow(
                            icon: "folder.fill",
                            title: "Pinboards",
                            description: "Organize clips into collections"
                        )

                        Divider()
                            .background(Color.white.opacity(0.1))

                        FeatureRow(
                            icon: "link",
                            title: "Link Previews",
                            description: "Rich previews for URLs"
                        )
                    }
                }
            }

            // Upgrade Section
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeader("Upgrade", icon: "arrow.up.circle")

                SettingsCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Paste Pro")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Unlock all features")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text("$9.99/year")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("or $1.99/month")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Button {
                            // TODO: Implement subscription
                        } label: {
                            Text("Upgrade to Pro")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(true)
                        .accessibilityIdentifier("settings.button.upgradeToPro")

                        Text("Coming soon")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }

            // Restore Section
            HStack {
                Spacer()

                Button("Restore Purchases") {
                    // TODO: Implement restore
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(true)
                .accessibilityIdentifier("settings.button.restorePurchases")
            }
        }
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 24, height: 24)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}

// Keep the old tab for compatibility
struct PurchaseTab: View {
    var body: some View {
        SubscriptionSettingsContent()
            .padding()
    }
}
