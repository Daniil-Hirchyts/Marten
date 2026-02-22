import SwiftUI

// MARK: - Animation Constants

enum MartenAnimation {
    static let springResponse: Double = 0.35
    static let springDamping: Double = 0.82
    static let quickSpringResponse: Double = 0.25
    static let quickSpringDamping: Double = 0.86

    static var smooth: Animation {
        .spring(response: springResponse, dampingFraction: springDamping)
    }

    static var quick: Animation {
        .spring(response: quickSpringResponse, dampingFraction: quickSpringDamping)
    }

    static var slideUp: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        )
    }

    static var fadeScale: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.95))
    }
}

// MARK: - iOS Button Size Standards

/// Standard button sizes following iOS Human Interface Guidelines
enum MartenButtonSize {
    /// Minimum tap target size recommended by Apple (44x44 points)
    static let minimumTapTarget: CGFloat = 44

    /// Standard icon button size (44x44 points)
    static let iconButton: CGFloat = 44

    /// Large icon button size (56x56 points)
    static let largeIconButton: CGFloat = 56

    /// Standard button height for text buttons
    static let standardHeight: CGFloat = 50

    /// Prominent button height
    static let prominentHeight: CGFloat = 52

    /// Compact button height (minimum recommended)
    static let compactHeight: CGFloat = 44
}
