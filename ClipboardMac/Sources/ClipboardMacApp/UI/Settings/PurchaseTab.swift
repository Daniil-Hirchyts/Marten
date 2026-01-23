import SwiftUI

struct SubscriptionSettingsContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeader("Subscription", icon: "star")

                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Free Plan")
                            .font(.system(size: 14, weight: .semibold))

                        Text("You're currently using the free version of Paste.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
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
