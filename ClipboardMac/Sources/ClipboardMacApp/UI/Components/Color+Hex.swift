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
    static func colorCircle(hex: String, size: CGFloat = 12) -> NSImage {
        let color = NSColor(hex: hex)
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        color.setFill()
        let path = NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: size, height: size))
        path.fill()
        image.unlockFocus()
        return image
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
        PinboardColor(name: "Purple", hex: "#8338EC"),
        PinboardColor(name: "Pink", hex: "#FF006E"),
        PinboardColor(name: "Orange", hex: "#FB5607"),
        PinboardColor(name: "Yellow", hex: "#FFBE0B")
    ]
    
    public static let colors = all.map { $0.hex }
    public static let defaultHex = all.first?.hex ?? "#8E8E93"
}
