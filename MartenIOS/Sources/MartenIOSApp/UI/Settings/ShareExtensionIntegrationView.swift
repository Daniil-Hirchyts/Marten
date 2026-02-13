import SwiftUI

struct ShareExtensionIntegrationView: View {
    var body: some View {
        IntegrationDetailView(
            icon: "square.and.arrow.up",
            iconColor: .green,
            title: "Enable Share Extension",
            description: "Save links, images, and text to Marten involving the iOS Share Sheet.",
            buttonTitle: "How to Enable",
            action: {}, 
            instructions: {
                VStack(alignment: .leading, spacing: 16) {
                    InstructionStep(number: 1, text: "Open Safari or any app with a Share button.")
                    InstructionStep(number: 2, text: "Tap the Share icon.")
                    InstructionStep(number: 3, text: "Scroll down to the bottom and tap \"Edit Actions...\".")
                    InstructionStep(number: 4, text: "Find \"Marten\" and tap the green + button.")
                    InstructionStep(number: 5, text: "Tap \"Done\".")
                }
            }
        )
    }
}
