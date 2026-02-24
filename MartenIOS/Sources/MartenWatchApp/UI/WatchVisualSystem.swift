import SwiftUI

enum WatchCardProminence {
    case subtle
    case normal
    case accent
    case critical
}

enum WatchVisualSystem {
    static let outerPadding: CGFloat = 10
    static let sectionSpacing: CGFloat = 8
    static let cardPadding: CGFloat = 10
    static let cornerRadius: CGFloat = 16
    static let floatingActionInset: CGFloat = 2
    static let floatingActionSize: CGFloat = 36
}

private struct WatchCardModifier: ViewModifier {
    let prominence: WatchCardProminence

    func body(content: Content) -> some View {
        content
            .padding(WatchVisualSystem.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: WatchVisualSystem.cornerRadius, style: .continuous)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: WatchVisualSystem.cornerRadius, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: 1)
            )
    }

    private var fillColor: Color {
        switch prominence {
        case .subtle:
            return .white.opacity(0.06)
        case .normal:
            return .white.opacity(0.1)
        case .accent:
            return .accentColor.opacity(0.22)
        case .critical:
            return .red.opacity(0.2)
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
        }
    }
}

extension View {
    func watchCard(prominence: WatchCardProminence = .normal) -> some View {
        modifier(WatchCardModifier(prominence: prominence))
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
        .controlSize(.mini)
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
        .padding(.bottom, WatchVisualSystem.floatingActionInset)
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
