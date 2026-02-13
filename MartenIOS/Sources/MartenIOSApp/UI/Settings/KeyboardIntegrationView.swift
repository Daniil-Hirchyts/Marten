import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct KeyboardIntegrationView: View {
    @State private var instructionsExpanded = false

    var body: some View {
        IntegrationDetailView(
            icon: "keyboard",
            iconColor: .blue,
            title: "Enable Keyboard",
            description: "Access your clipboard and paste snippets directly in any app using the Marten keyboard.",
            buttonTitle: "Go to Settings",
            action: openSettings,
            instructions: {
                VStack(alignment: .leading, spacing: 16) {
                    InstructionStep(number: 1, text: "Tap \"Keyboards\".")
                    InstructionStep(number: 2, text: "Enable \"Marten\".")
                    InstructionStep(number: 3, text: "Tap \"Allow Full Access\".")
                    InstructionStep(number: 4, text: "Confirm \"Allow\".")

                    Text("Why Full Access?")
                        .font(.headline)
                        .padding(.top, 8)

                    Text("Full Access is required for Marten to sync with your clipboard history and pinboards. We respect your privacy and do not transmit your keystrokes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        )
    }

    private func openSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

