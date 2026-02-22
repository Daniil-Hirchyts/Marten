import SwiftUI

// MARK: - Glass Surface

struct MartenGlassSurface<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    let isInteractive: Bool
    @ViewBuilder let content: Content

    init(
        cornerRadius: CGFloat = 16,
        padding: CGFloat = 12,
        isInteractive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.isInteractive = isInteractive
        self.content = content()
    }

    var body: some View {
        #if os(iOS)
            if #available(iOS 26, *) {
                content
                    .padding(padding)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.clear)
                    )
                    .glassEffect(
                        isInteractive ? .regular.interactive() : .regular,
                        in: .rect(cornerRadius: cornerRadius)
                    )
            } else {
                fallbackSurface
            }
        #else
            fallbackSurface
        #endif
    }

    private var fallbackSurface: some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
            )
    }
}

// MARK: - Glass Card (optimized for item cards)

struct MartenGlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let isSelected: Bool
    @ViewBuilder let content: Content

    init(
        cornerRadius: CGFloat = 18,
        isSelected: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.isSelected = isSelected
        self.content = content()
    }

    var body: some View {
        #if os(iOS)
            if #available(iOS 26, *) {
                content
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.clear)
                    )
                    .glassEffect(
                        .regular.interactive(),  // No tint on selection
                        in: .rect(cornerRadius: cornerRadius)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(
                                isSelected ? Color.accentColor : .clear,
                                lineWidth: isSelected ? 3 : 0
                            )
                    )
            } else {
                fallbackCard
            }
        #else
            fallbackCard
        #endif
    }

    private var fallbackCard: some View {
        content
            .padding(14)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        isSelected ? Color.accentColor : .white.opacity(0.14),
                        lineWidth: isSelected ? 3 : 1
                    )
            )
    }
}

// MARK: - Glass Container

struct MartenGlassContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        #if os(iOS)
            if #available(iOS 26, *) {
                GlassEffectContainer(spacing: spacing) {
                    content
                }
            } else {
                content
            }
        #else
            content
        #endif
    }
}

struct MartenGlassSection<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        MartenGlassSurface(cornerRadius: 16, padding: 0) {
            VStack(spacing: spacing) {
                content
            }
            .padding(.vertical, 8)
        }
    }
}
