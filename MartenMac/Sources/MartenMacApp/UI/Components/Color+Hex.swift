import Foundation
import SwiftUI
import AppKit

extension Color {
    init(hex: String, fallback: Color = .gray) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6 else {
            self = fallback
            return
        }

        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else {
            self = fallback
            return
        }

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self = Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}

extension NSImage {
    static func colorCircle(hex: String, size: CGFloat = 14) -> NSImage {
        let color = NSColor(hex: hex)
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        color.setFill()
        let path = NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: size, height: size))
        path.fill()
        image.unlockFocus()
        return image
    }

    /// Pre-renders [checkmark] [circle] [lock] as a single NSImage for native macOS menus.
    /// Only the first Image in an NSMenuItem label is rendered; everything must live here.
    /// Fixed-width frames + opacity keep all rows the same width for alignment.
    @MainActor
    static func pinboardMenuIcon(colorHex: String, sign: String?, size: CGFloat, isAssigned: Bool, isLocked: Bool, colorScheme: ColorScheme = .dark) -> NSImage {
        let indicatorSize = size * 0.68
        let iconColor: Color = colorScheme == .dark ? .white : .black
        let renderer = ImageRenderer(content:
            HStack(alignment: .center, spacing: 5) {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.62, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: indicatorSize)
                    .opacity(isAssigned ? 1 : 0)
                PinboardIndicator(colorHex: colorHex, sign: sign, size: size, showBorder: false)
                Image(systemName: "lock.fill")
                    .font(.system(size: size * 0.6, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: indicatorSize)
                    .opacity(isLocked ? 1 : 0)
            }
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        return renderer.nsImage ?? colorCircle(hex: colorHex, size: size)
    }
}

extension NSColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = CGFloat((value >> 16) & 0xFF) / 255.0
        let green = CGFloat((value >> 8) & 0xFF) / 255.0
        let blue = CGFloat(value & 0xFF) / 255.0
        self.init(srgbRed: red, green: green, blue: blue, alpha: 1.0)
    }
}

public struct PinboardColor: Hashable {
    public let name: String
    public let hex: String
}

public enum PinboardPalette {
    public static let all = [
        PinboardColor(name: "Blue", hex: "#3A86FF"),
        PinboardColor(name: "Indigo", hex: "#5A67D8"),
        PinboardColor(name: "Violet", hex: "#7C4DFF"),
        PinboardColor(name: "Purple", hex: "#8338EC"),
        PinboardColor(name: "Pink", hex: "#FF006E"),
        PinboardColor(name: "Rose", hex: "#FF4D9D"),
        PinboardColor(name: "Red", hex: "#E63946"),
        PinboardColor(name: "Coral", hex: "#FF7F50"),
        PinboardColor(name: "Orange", hex: "#FB5607"),
        PinboardColor(name: "Amber", hex: "#FF9F1C"),
        PinboardColor(name: "Yellow", hex: "#FFBE0B"),
        PinboardColor(name: "Lime", hex: "#9BC53D"),
        PinboardColor(name: "Green", hex: "#2A9D8F"),
        PinboardColor(name: "Teal", hex: "#00BFA6"),
        PinboardColor(name: "Cyan", hex: "#48CAE4"),
        PinboardColor(name: "Slate", hex: "#6C757D")
    ]

    public static let colors = all.map { $0.hex }
    public static let defaultHex = all.first?.hex ?? "#8E8E93"
}
