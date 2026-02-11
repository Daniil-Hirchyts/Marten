import SwiftUI

struct SubscriptionSection: View {
    var body: some View {
        MartenGlassSurface(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Subscription", systemImage: "star")
                    .font(.headline)

                Text("Free Plan")
                    .font(.subheadline.weight(.semibold))

                Text("You are currently using the free version of Marten.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
