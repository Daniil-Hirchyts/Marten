import SwiftUI

// MARK: - Buttons

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
                Button(action: action) {
                    label
                        .frame(minHeight: MartenButtonSize.prominentHeight)
                }
                .buttonStyle(.glassProminent)
            } else {
                Button(action: action) {
                    label
                        .frame(minHeight: MartenButtonSize.prominentHeight)
                }
                .buttonStyle(.borderedProminent)
            }
        #else
            Button(action: action) {
                label
                    .frame(minHeight: MartenButtonSize.prominentHeight)
            }
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
                Button(action: action) {
                    label
                        .frame(minHeight: MartenButtonSize.standardHeight)
                }
                .buttonStyle(.glass)
            } else {
                Button(action: action) {
                    label
                        .frame(minHeight: MartenButtonSize.standardHeight)
                }
                .buttonStyle(.bordered)
            }
        #else
            Button(action: action) {
                label
                    .frame(minHeight: MartenButtonSize.standardHeight)
            }
            .buttonStyle(.bordered)
        #endif
    }
}

/// Icon-only button with proper iOS tap target size
struct MartenIconButton: View {
    let systemImage: String
    let action: () -> Void
    let size: CGFloat
    let tint: Color?

    init(
        systemImage: String,
        size: CGFloat = MartenButtonSize.iconButton,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.size = max(size, MartenButtonSize.minimumTapTarget)  // Enforce minimum
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .semibold))
                .frame(width: size, height: size)
                .contentShape(Rectangle())
                .foregroundStyle(tint ?? .primary)
        }
        .buttonStyle(.plain)
    }
}
