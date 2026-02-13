import SwiftUI

struct PinboardSelectionRow: View {
    enum Leading {
        case all
        case pinboard(colorHex: String, sign: String?)
    }

    struct LockState {
        let isLocked: Bool
        let canAccess: Bool
    }

    let leading: Leading
    let title: String
    var showsSharedBadge: Bool = false
    var showsSelectionCheckmark: Bool = false
    var isSelected: Bool = false
    var lockState: LockState? = nil
    var cornerRadius: CGFloat = 999

    var body: some View {
        MartenGlassSurface(cornerRadius: cornerRadius, padding: 0, isInteractive: false) {
            HStack(spacing: 12) {
                leadingView

                titleView

                Spacer()

                if showsSelectionCheckmark, isSelected {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(Color.accentColor)
                }

                if showsSharedBadge {
                    Image(systemName: "person.2.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let lockState, lockState.isLocked {
                    Image(systemName: lockState.canAccess ? "lock.open.fill" : "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private var leadingView: some View {
        switch leading {
        case .all:
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: "tray.2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        case .pinboard(let colorHex, let sign):
            PinboardIndicator(colorHex: colorHex, sign: sign, size: 32)
        }
    }

    @ViewBuilder
    private var titleView: some View {
        switch leading {
        case .all:
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        case .pinboard:
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
    }
}
