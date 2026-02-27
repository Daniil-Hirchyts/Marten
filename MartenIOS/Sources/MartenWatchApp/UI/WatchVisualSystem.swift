import SwiftUI

enum WatchCardProminence {
    case subtle
    case normal
    case accent
    case critical
    case tinted(Color)
}

enum WatchVisualSystem {
    static let outerPadding: CGFloat = 10
    static let sectionSpacing: CGFloat = 8
    static let cardPadding: CGFloat = 10
    static let cornerRadius: CGFloat = 16
    static let itemPreviewHeight: CGFloat = 34
    static let floatingActionInset: CGFloat = 2
    static let floatingActionBottomInset: CGFloat = 10
    static let floatingActionSize: CGFloat = 40
}

private struct WatchCardModifier: ViewModifier {
    let prominence: WatchCardProminence
    var customPadding: EdgeInsets?

    func body(content: Content) -> some View {
        content
            .padding(customPadding ?? EdgeInsets(
                top: WatchVisualSystem.cardPadding + 4,
                leading: WatchVisualSystem.cardPadding,
                bottom: WatchVisualSystem.cardPadding + 4,
                trailing: WatchVisualSystem.cardPadding
            ))
            .background(
                RoundedRectangle(cornerRadius: WatchVisualSystem.cornerRadius, style: .continuous)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: WatchVisualSystem.cornerRadius, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: 1)
            )
    }

    private var fillColor: AnyShapeStyle {
        switch prominence {
        case .subtle:
            return AnyShapeStyle(Color.white.opacity(0.06))
        case .normal:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.white.opacity(0.15), Color.white.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .accent:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.15)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .critical:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.red.opacity(0.3), Color.red.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .tinted(let color):
            return AnyShapeStyle(
                LinearGradient(
                    colors: [color.opacity(0.25), color.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    private var strokeColor: Color {
        switch prominence {
        case .subtle:
            return .white.opacity(0.08)
        case .normal:
            return .white.opacity(0.12)
        case .accent:
            return .accentColor.opacity(0.4)
        case .critical:
            return .red.opacity(0.35)
        case .tinted(let color):
            return color.opacity(0.3)
        }
    }
}

extension View {
    func watchCard(prominence: WatchCardProminence = .normal, padding: EdgeInsets? = nil) -> some View {
        modifier(WatchCardModifier(prominence: prominence, customPadding: padding))
    }

    @ViewBuilder
    func watchStandardGlassButtonStyle() -> some View {
        if #available(watchOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func watchProminentGlassButtonStyle() -> some View {
        if #available(watchOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}

struct WatchFloatingGlassActionButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
        }
        .watchStandardGlassButtonStyle()
        .labelStyle(.iconOnly)
        .buttonBorderShape(.circle)
        .frame(
            width: WatchVisualSystem.floatingActionSize,
            height: WatchVisualSystem.floatingActionSize,
            alignment: .center
        )
        .fixedSize()
        .contentShape(Circle())
        .accessibilityLabel(accessibilityLabel)
        .padding(.trailing, WatchVisualSystem.floatingActionInset)
        .padding(.bottom, WatchVisualSystem.floatingActionBottomInset)
    }
}

struct WatchFloatingTextFieldLinkActionButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let prompt: String
    let onSubmit: (String) -> Void

    var body: some View {
        TextFieldLink(prompt: Text(prompt), label: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
        }, onSubmit: onSubmit)
        .watchStandardGlassButtonStyle()
        .labelStyle(.iconOnly)
        .buttonBorderShape(.circle)
        .frame(
            width: WatchVisualSystem.floatingActionSize,
            height: WatchVisualSystem.floatingActionSize,
            alignment: .center
        )
        .fixedSize()
        .contentShape(Circle())
        .accessibilityLabel(accessibilityLabel)
        .padding(.trailing, WatchVisualSystem.floatingActionInset)
        .padding(.bottom, WatchVisualSystem.floatingActionBottomInset)
    }
}

struct WatchMetadataPill: View {
    let title: String
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }

            Text(title)
                .lineLimit(1)
        }
        .font(.caption2)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.18), in: Capsule())
        .foregroundStyle(tint)
    }
}

struct WatchSectionTitle: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 2)
    }
}

struct WatchPinboardIcon: View {
    let iconName: String?
    let tint: Color

    var body: some View {
        Group {
            if let iconName,
                iconName.containsEmoji,
                !iconName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                Text(iconName)
                    .font(.body)
            } else {
                Image(systemName: iconName ?? "tray")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: 30, height: 30)
        .background(tint.opacity(0.16), in: Circle())
    }
}

extension String {
    var containsEmoji: Bool {
        unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && scalar.value > 0x238C)
        }
    }
}

struct WatchCardButtonStyle: ButtonStyle {
    var prominence: WatchCardProminence = .normal

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .watchCard(prominence: prominence, padding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct WatchCardCopiedOverlay: View {
    let isVisible: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: WatchVisualSystem.cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)

            VStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Copied")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1.0 : 0.9)
        .allowsHitTesting(false)
    }
}

struct WatchFloatingTextFieldBindingActionButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let title: String
    @Binding var text: String
    let onSubmit: () -> Void

    var body: some View {
        ZStack {
            Button(action: {}) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
            }
            .watchStandardGlassButtonStyle()
            .labelStyle(.iconOnly)
            .buttonBorderShape(.circle)
            .allowsHitTesting(false)
            
            TextField(title, text: $text)
                .labelsHidden()
                .opacity(0.011)
                .onSubmit(onSubmit)
        }
        .frame(
            width: WatchVisualSystem.floatingActionSize,
            height: WatchVisualSystem.floatingActionSize,
            alignment: .center
        )
        .fixedSize()
        .contentShape(Circle())
        .accessibilityLabel(accessibilityLabel)
        .padding(.trailing, WatchVisualSystem.floatingActionInset)
        .padding(.bottom, WatchVisualSystem.floatingActionBottomInset)
    }
}
