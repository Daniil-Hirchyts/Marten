import SwiftUI

#if canImport(UIKit)
import UIKit

typealias PlatformColor = UIColor

extension PlatformColor {
    static var platformTertiaryLabel: PlatformColor { .tertiaryLabel }
    static var platformSystemBackground: PlatformColor { .systemBackground }
    static var platformSystemGroupedBackground: PlatformColor { .systemGroupedBackground }
    static var platformSecondarySystemGroupedBackground: PlatformColor { .secondarySystemGroupedBackground }
}

extension Color {
    init(platformColor: PlatformColor) {
        self.init(uiColor: platformColor)
    }
}
#elseif canImport(AppKit)
import AppKit

typealias PlatformColor = NSColor

extension PlatformColor {
    static var platformTertiaryLabel: PlatformColor { .tertiaryLabelColor }
    static var platformSystemBackground: PlatformColor { .windowBackgroundColor }
    static var platformSystemGroupedBackground: PlatformColor { .windowBackgroundColor }
    static var platformSecondarySystemGroupedBackground: PlatformColor { .controlBackgroundColor }
}

extension Color {
    init(platformColor: PlatformColor) {
        self.init(nsColor: platformColor)
    }
}
#endif

