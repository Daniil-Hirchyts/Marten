import MartenIOSApp
import SwiftUI

struct ShareRootView: View {
    let payloadCount: Int
    let pinboards: [SharedPinboardSummary]
    let isLoading: Bool
    let isSaving: Bool
    let errorMessage: String?
    let onSave: (UUID?) -> Void
    let onCancel: () -> Void

    @State private var selectedPinboardID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section("Incoming Content") {
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("Preparing shared content…")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("\(payloadCount) item(s) ready to save")
                            .foregroundStyle(payloadCount > 0 ? .primary : .secondary)
                    }
                }

                Section("Destination") {
                    Picker("Save To", selection: $selectedPinboardID) {
                        Text("All")
                            .tag(Optional<UUID>.none)
                        ForEach(pinboards.filter { !$0.isSystemMarten }) { pinboard in
                            Text(pinboard.name)
                                .tag(Optional(pinboard.id))
                        }
                    }
                }

                if let errorMessage, !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Save to Marten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        onSave(selectedPinboardID)
                    }
                    .disabled(isLoading || payloadCount == 0 || isSaving)
                }
            }
        }
    }
}
