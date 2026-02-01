import SwiftUI

// MARK: - Design Tokens

/// Semantic design tokens for consistent styling across the app
enum DesignTokens {
    enum Opacity {
        /// Subtle background for inactive states
        static let backgroundSubtle: CGFloat = 0.08

        /// Medium background for button backgrounds, hover states
        static let backgroundMedium: CGFloat = 0.15

        /// Strong background for active/focused states
        static let backgroundStrong: CGFloat = 0.25

        /// Card background (content, not navigation)
        static let cardBackground: CGFloat = 0.12

        /// Card background when selected
        static let cardBackgroundSelected: CGFloat = 0.18

        /// Subtle border for inactive states
        static let borderSubtle: CGFloat = 0.12

        /// Medium border for default states
        static let borderMedium: CGFloat = 0.25

        /// Strong border for selected/focused states
        static let borderStrong: CGFloat = 0.40
    }

    enum Spacing {
        static let cardCornerRadius: CGFloat = 20
        static let buttonCornerRadius: CGFloat = 10
        static let iconSize: CGFloat = 14
    }
}

// MARK: - Glass Shape Styles

/// Defines the shape for glass effects
enum GlassShape {
    case circle
    case capsule
    case roundedRectangle(cornerRadius: CGFloat)
}

// MARK: - Glass Effect Modifiers

@available(macOS 26.0, *)
extension View {
    /// Apply glass effect to navigation controls (buttons, tabs)
    func glassNavigationStyle(shape: GlassShape = .capsule) -> some View {
        modifier(GlassNavigationModifier(shape: shape, isProminent: false))
    }

    /// Apply prominent glass for primary actions or selected states
    func glassProminentStyle(shape: GlassShape = .capsule) -> some View {
        modifier(GlassNavigationModifier(shape: shape, isProminent: true))
    }

    /// Apply glass effect for circular buttons
    func glassCircleButton() -> some View {
        modifier(GlassNavigationModifier(shape: .circle, isProminent: false))
    }

    /// Apply glass effect with conditional prominence
    func glassStyle(shape: GlassShape = .capsule, isProminent: Bool = false) -> some View {
        modifier(GlassNavigationModifier(shape: shape, isProminent: isProminent))
    }
}

@available(macOS 26.0, *)
private struct GlassNavigationModifier: ViewModifier {
    let shape: GlassShape
    let isProminent: Bool

    func body(content: Content) -> some View {
        // For prominent (selected) state, use a slightly brighter glass without full white tint
        // This maintains readability while showing selection
        switch shape {
        case .circle:
            if isProminent {
                content
                    .glassEffect(.regular, in: .circle)
                    .brightness(0.1)
                    .contentShape(Circle())
            } else {
                content
                    .glassEffect(.regular, in: .circle)
                    .contentShape(Circle())
            }
        case .capsule:
            if isProminent {
                content
                    .glassEffect(.regular, in: .capsule)
                    .brightness(0.1)
                    .contentShape(Capsule())
            } else {
                content
                    .glassEffect(.regular, in: .capsule)
                    .contentShape(Capsule())
            }
        case .roundedRectangle(let cornerRadius):
            if isProminent {
                content
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius, style: .continuous))
                    .brightness(0.1)
                    .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                content.glassEffect(
                    .regular, in: .rect(cornerRadius: cornerRadius, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
    }
}

// MARK: - Fallback Styles for macOS < 26

/// Fallback background modifier for pre-macOS 26
struct FallbackGlassBackground: ViewModifier {
    let shape: GlassShape
    let isSelected: Bool
    let isHovering: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let opacity: CGFloat = {
            if isSelected {
                return DesignTokens.Opacity.backgroundStrong
            }
            if isHovering {
                return DesignTokens.Opacity.backgroundMedium
            }
            return DesignTokens.Opacity.backgroundSubtle
        }()

        content.background(
            Group {
                switch shape {
                case .circle:
                    Circle().fill(adaptiveColor(opacity: opacity))
                case .capsule:
                    Capsule().fill(adaptiveColor(opacity: opacity))
                case .roundedRectangle(let cornerRadius):
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(adaptiveColor(opacity: opacity))
                }
            }
        )
    }

    private func adaptiveColor(opacity: CGFloat) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(opacity)
            : Color.black.opacity(opacity)
    }
}

extension View {
    /// Fallback glass-like background for pre-macOS 26
    func fallbackGlassBackground(
        shape: GlassShape = .capsule,
        isSelected: Bool = false,
        isHovering: Bool = false
    ) -> some View {
        modifier(FallbackGlassBackground(shape: shape, isSelected: isSelected, isHovering: isHovering)
        )
    }
}

// MARK: - Conditional Glass Application

extension View {
    /// Apply glass effect on macOS 26+, fallback otherwise
    @ViewBuilder
    func adaptiveGlassBackground(
        shape: GlassShape = .capsule,
        isSelected: Bool = false,
        isHovering: Bool = false
    ) -> some View {
        if #available(macOS 26.0, *) {
            self.glassStyle(shape: shape, isProminent: isSelected)
        } else {
            self.fallbackGlassBackground(shape: shape, isSelected: isSelected, isHovering: isHovering)
        }
    }
}
