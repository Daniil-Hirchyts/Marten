import SwiftUI

enum OverlayAnimation {
    // MARK: - Spring Animations

    /// Standard search bar expand/collapse spring.
    static let searchSpring = Animation.spring(response: 0.3, dampingFraction: 0.8)

    /// Card reorder / pin toggle spring.
    static let cardSpring = Animation.spring(response: 0.32, dampingFraction: 0.86)

    /// Pinboard create/cancel spring.
    static let pinboardSpring = Animation.spring(response: 0.3, dampingFraction: 0.75)

    // MARK: - Ease Animations

    /// Standard transition (hover reveals, lock state, share tabs).
    static let standardTransition = Animation.easeInOut(duration: 0.2)

    /// Quick interactive transition (hover states, scroll-to, filter chips).
    static let quickTransition = Animation.easeInOut(duration: 0.15)

    /// Pinboard tab selection.
    static let pinboardSelect = Animation.easeOut(duration: 0.14)

    /// Fast drag opacity fade.
    static let dragFade = Animation.easeOut(duration: 0.1)
}
