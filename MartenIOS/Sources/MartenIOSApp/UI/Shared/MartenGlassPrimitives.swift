import SwiftUI

struct MartenGlassSurface<Content: View>: View {
    let cornerRadius: CGFloat
    let isInteractive: Bool
    @ViewBuilder let content: Content

    init(
        cornerRadius: CGFloat = 16,
        isInteractive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.isInteractive = isInteractive
        self.content = content()
    }

    var body: some View {
        #if os(iOS)
        if #available(iOS 26, *) {
            content
                .padding(12)
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
            .padding(12)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
            )
    }
}

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

struct MartenGlassProminentButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label

    init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    var body: some View {
        #if os(iOS)
        if #available(iOS 26, *) {
            Button(action: action) { label }
                .buttonStyle(.glassProminent)
        } else {
            Button(action: action) { label }
                .buttonStyle(.borderedProminent)
        }
        #else
        Button(action: action) { label }
            .buttonStyle(.borderedProminent)
        #endif
    }
}

struct MartenGlassButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label

    init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    var body: some View {
        #if os(iOS)
        if #available(iOS 26, *) {
            Button(action: action) { label }
                .buttonStyle(.glass)
        } else {
            Button(action: action) { label }
                .buttonStyle(.bordered)
        }
        #else
        Button(action: action) { label }
            .buttonStyle(.bordered)
        #endif
    }
}
