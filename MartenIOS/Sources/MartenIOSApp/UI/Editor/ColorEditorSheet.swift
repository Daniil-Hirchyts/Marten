import MartenCore
import SwiftUI

struct ColorEditorSheet: View {
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var colorInput: String
    @State private var pickerColor: Color

    init(item: ClipItem, onSave: @escaping (String) -> Void) {
        self.onSave = onSave
        let initialHex = ColorHex.normalizedHex(from: item.primaryText ?? "") ?? "#808080"
        _colorInput = State(initialValue: initialHex)
        _pickerColor = State(initialValue: Color(hex: initialHex, fallback: .gray))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    previewSwatch

                    HStack {
                        Image(systemName: "paintpalette.fill")
                            .foregroundStyle(.secondary)
                        Text("Choose Color")
                            .foregroundStyle(.primary)
                        Spacer()
                        ColorPicker("Choose Color", selection: $pickerColor, supportsOpacity: false)
                            .labelsHidden()
                            .onChange(of: pickerColor) { _, newColor in
                                if let hex = newColor.hexString {
                                    colorInput = hex
                                }
                            }
                    }
                    .padding(14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                    TextField("#RRGGBB", text: $colorInput)
                        .font(.system(.body, design: .monospaced))
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        #endif
                        .padding(14)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .onChange(of: colorInput) { _, newValue in
                            if let hex = ColorHex.normalizedHex(from: newValue) {
                                pickerColor = Color(hex: hex, fallback: .gray)
                            }
                        }
                }
                .padding(16)
            }
            .navigationTitle("Edit Color")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        guard let normalizedHex else { return }
                        onSave(normalizedHex)
                        dismiss()
                    }
                    .disabled(normalizedHex == nil)
                }
            }
        }
    }

    private var normalizedHex: String? {
        ColorHex.normalizedHex(from: colorInput)
    }

    private var previewSwatch: some View {
        let colorHex = normalizedHex ?? "#808080"
        let foreground = ColorHex.foregroundColor(for: colorHex)

        return RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(hex: colorHex, fallback: .gray))
            .frame(height: 160)
            .overlay {
                Text(colorHex)
                    .font(.system(.title2, design: .monospaced).weight(.bold))
                    .foregroundStyle(foreground)
            }
    }
}

private extension Color {
    var hexString: String? {
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else { return nil }
        let r = Int(round(components[0] * 255))
        let g = Int(round(components[1] * 255))
        let b = Int(round(components[2] * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
