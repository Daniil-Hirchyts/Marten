import SwiftUI

struct SubscriptionSection: View {
    var body: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "star.fill")
                    .font(.title3)
                    .foregroundStyle(.yellow)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Free Plan")
                        .font(.subheadline.weight(.semibold))
                    Text("All core features included")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        } header: {
            Label("Subscription", systemImage: "star")
        }
    }
}
