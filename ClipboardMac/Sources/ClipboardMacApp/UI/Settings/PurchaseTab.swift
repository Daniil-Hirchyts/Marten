import SwiftUI

struct PurchaseTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "checkmark.seal.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .foregroundStyle(.green)
            
            Text("Paste Pro")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Thank you for your purchase!")
                .foregroundStyle(.secondary)
            
            Text("You have full access to all features.")
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Button("Restore Purchases") {
                // Placeholder
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("settings.button.restorePurchases")
            .accessibilityLabel("Restore purchases")
            
            Spacer()
        }
        .padding()
    }
}
