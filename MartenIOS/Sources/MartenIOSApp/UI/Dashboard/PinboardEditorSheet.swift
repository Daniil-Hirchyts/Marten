import SwiftUI

struct PinboardEditorSheet: View {
    enum Mode {
        case create
        case edit

        var title: String {
            switch self {
            case .create:
                return "New Pinboard"
            case .edit:
                return "Edit Pinboard"
            }
        }

        var actionLabel: String {
            switch self {
            case .create:
                return "Create"
            case .edit:
                return "Save"
            }
        }
    }

    let mode: Mode
    let initialName: String
    let initialColorHex: String
    let initialIconName: String?
    let onSave: (_ name: String, _ colorHex: String, _ iconName: String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var selectedColorHex: String
    @State private var iconName: String

    init(
        mode: Mode,
        initialName: String = "",
        initialColorHex: String = PinboardColorPalette.defaultHex,
        initialIconName: String? = nil,
        onSave: @escaping (_ name: String, _ colorHex: String, _ iconName: String?) -> Void
    ) {
        self.mode = mode
        self.initialName = initialName
        self.initialColorHex = initialColorHex
        self.initialIconName = initialIconName
        self.onSave = onSave

        _name = State(initialValue: initialName)
        _selectedColorHex = State(initialValue: initialColorHex)
        _iconName = State(initialValue: initialIconName ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    nameTextField
                }

                Section("Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], spacing: 10) {
                        ForEach(PinboardColorPalette.all, id: \.hex) { option in
                            Button {
                                selectedColorHex = option.hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: option.hex, fallback: .gray))
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                selectedColorHex == option.hex ? Color.primary : .clear,
                                                lineWidth: 2
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.name)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Icon (Optional)") {
                    iconTextField
                }
            }
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.actionLabel) {
                        onSave(
                            name.trimmingCharacters(in: .whitespacesAndNewlines),
                            selectedColorHex,
                            iconName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? nil
                                : iconName.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var nameTextField: some View {
        #if os(iOS)
        TextField("Pinboard name", text: $name)
            .textInputAutocapitalization(.words)
        #else
        TextField("Pinboard name", text: $name)
        #endif
    }

    private var iconTextField: some View {
        #if os(iOS)
        TextField("SF Symbol name", text: $iconName)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        TextField("SF Symbol name", text: $iconName)
        #endif
    }
}
