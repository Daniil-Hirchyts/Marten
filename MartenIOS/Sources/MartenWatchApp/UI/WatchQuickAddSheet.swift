import SwiftUI

struct WatchQuickAddSheet: View {
    @Bindable var container: MartenWatchContainer

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WatchVisualSystem.sectionSpacing) {
                    destinationCard
                    composerCard
                }
                .padding(.horizontal, WatchVisualSystem.outerPadding)
                .padding(.bottom, 58)
            }
            .navigationTitle("New Card")
            .safeAreaInset(edge: .bottom) {
                saveButton
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            WatchSectionTitle(title: "New Card", detail: "\(characterCount)")

            Label(container.selectedPinboardTitle, systemImage: "tray")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .watchCard(prominence: .subtle)
    }

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Type or dictate", text: $text, axis: .vertical)
                .lineLimit(4...12)
                .font(.body)

            Text("Cards are added to \(container.selectedPinboardTitle).")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .watchCard(prominence: .accent)
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            HStack(spacing: 6) {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(isSaving ? "Saving" : "Save Card")
                    .frame(maxWidth: .infinity)
            }
        }
        .watchProminentGlassButtonStyle()
        .buttonBorderShape(.capsule)
        .disabled(isSaveDisabled)
        .padding(.horizontal, WatchVisualSystem.outerPadding)
        .padding(.top, 4)
    }

    private var characterCount: Int {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    private var isSaveDisabled: Bool {
        isSaving || characterCount == 0
    }

    private func save() {
        guard !isSaveDisabled else { return }
        isSaving = true

        Task { @MainActor in
            let saved = await container.createTextItem(text)
            isSaving = false
            if saved {
                dismiss()
            }
        }
    }
}
