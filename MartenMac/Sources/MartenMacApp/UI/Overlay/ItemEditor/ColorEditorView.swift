import AppKit
import MartenCore
import SwiftUI

@MainActor
struct ColorEditorView: View {
    @Binding var hexText: String

    @State private var pickerColor: Color
    @State private var editingHex: String

    init(hexText: Binding<String>) {
        self._hexText = hexText
        let normalized = Self.normalizeHex(hexText.wrappedValue) ?? "#808080"
        self._pickerColor = State(initialValue: Color(hex: normalized, fallback: .gray))
        self._editingHex = State(initialValue: normalized)
    }

    var body: some View {
        VStack(spacing: 0) {
            swatch
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

            VStack(spacing: 12) {

                // Hex text field
                HStack(spacing: 8) {
                    Image(systemName: "number")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("#RRGGBB", text: $editingHex)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .textFieldStyle(.plain)
                        .onChange(of: editingHex) { _, newValue in
                            if let hex = Self.normalizeHex(newValue) {
                                pickerColor = Color(hex: hex, fallback: .gray)
                                hexText = hex
                            }
                        }
                    if Self.normalizeHex(editingHex) != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 12))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: hexText) { _, newValue in
            if let normalized = Self.normalizeHex(newValue), normalized != editingHex {
                editingHex = normalized
                pickerColor = Color(hex: normalized, fallback: .gray)
            }
        }
    }

    private var swatch: some View {
        let colorHex = Self.normalizeHex(editingHex) ?? "#808080"
        let bgColor = Color(hex: colorHex, fallback: .gray)
        let fgColor = foregroundColor(for: colorHex)

        return RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(bgColor)
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .overlay {
                VStack(spacing: 6) {
                    Text(colorHex)
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .foregroundStyle(fgColor)
                        .textSelection(.enabled)

                    Text(rgbLabel(for: colorHex))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(fgColor.opacity(0.7))
                }
            }
    }

    // MARK: - Helpers

    static func normalizeHex(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var s = trimmed
        if s.lowercased().hasPrefix("0x") { s = String(s.dropFirst(2)) }
        if s.hasPrefix("#") { s = String(s.dropFirst()) }
        let cleaned = s.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)

        if cleaned.count == 3 {
            let chars = Array(cleaned)
            return "#\(String(repeating: String(chars[0]), count: 2))\(String(repeating: String(chars[1]), count: 2))\(String(repeating: String(chars[2]), count: 2))".uppercased()
        }
        if cleaned.count == 6 { return "#\(cleaned)".uppercased() }
        if cleaned.count == 8 {
            let start = cleaned.startIndex
            return "#\(String(cleaned[start..<cleaned.index(start, offsetBy: 6)]))".uppercased()
        }
        return nil
    }

    private func foregroundColor(for hex: String) -> Color {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return .white }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance > 0.6 ? .black : .white
    }

    private func rgbLabel(for hex: String) -> String {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return "" }
        let r = Int((value >> 16) & 0xFF)
        let g = Int((value >> 8) & 0xFF)
        let b = Int(value & 0xFF)
        return "R \(r)  G \(g)  B \(b)"
    }
}

extension Color {
    var hexStringMac: String? {
        guard let components = NSColor(self).usingColorSpace(.sRGB)?.cgColor.components,
              components.count >= 3 else { return nil }
        let r = Int(round(components[0] * 255))
        let g = Int(round(components[1] * 255))
        let b = Int(round(components[2] * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
