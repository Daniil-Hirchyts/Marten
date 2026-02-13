import SwiftUI

struct SiriIntegrationView: View {
    var body: some View {
        IntegrationDetailView(
            icon: "sparkles",
            iconColor: .purple,
            title: "Siri & Shortcuts",
            description: "Automate your workflow with Marten actions in the Shortcuts app.",
            buttonTitle: "Open Shortcuts",
            action: openShortcuts,
            instructions: {
                VStack(alignment: .leading, spacing: 16) {
                    InstructionStep(number: 1, text: "Open the Shortcuts app.")
                    InstructionStep(number: 2, text: "Create a new shortcut.")
                    InstructionStep(number: 3, text: "Search for \"Marten\" in the action list.")
                    InstructionStep(number: 4, text: "Add actions like \"Add to Pinboard\" or \"Get Clipboard History\".")
                }
            }
        )
    }

    private func openShortcuts() {
        #if canImport(UIKit)
        if let url = URL(string: "shortcuts://") {
            UIApplication.shared.open(url)
        }
        #endif
    }
}
