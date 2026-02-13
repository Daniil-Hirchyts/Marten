import SwiftUI

struct WidgetsIntegrationView: View {
    var body: some View {
        IntegrationDetailView(
            icon: "widget.small",
            iconColor: .orange,
            title: "Add Widgets",
            description: "Access your pinboards and clipboard history right from your Home Screen or Lock Screen.",
            buttonTitle: "How to Add",
            action: {}, 
            instructions: {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Home Screen")
                        .font(.headline)
                    
                    InstructionStep(number: 1, text: "Long press anywhere on your Home Screen.")
                    InstructionStep(number: 2, text: "Tap the + button in the top left corner.")
                    InstructionStep(number: 3, text: "Search for \"Marten\".")
                    InstructionStep(number: 4, text: "Choose a widget and tap \"Add Widget\".")

                    Divider()
                        .padding(.vertical, 8)

                    Text("Lock Screen")
                        .font(.headline)

                    InstructionStep(number: 1, text: "Long press on your Lock Screen and tap \"Customize\".")
                    InstructionStep(number: 2, text: "Tap the widget area below the clock.")
                    InstructionStep(number: 3, text: "Find \"Marten\" in the list.")
                    InstructionStep(number: 4, text: "Tap or drag widgets to add them.")
                }
            }
        )
    }
}
