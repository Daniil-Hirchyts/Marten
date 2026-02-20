import SwiftUI

struct MartenSwipeActionIcon: View {
    let systemName: String
    let backgroundColor: Color
    var foregroundColor: Color = .white
    var label: String? = nil

    var tapTarget: CGFloat = 28
    var visualSize: CGFloat = 20

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: visualSize, height: visualSize)
                Image(systemName: systemName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(foregroundColor)
            }

            if let label {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(foregroundColor)
                    .lineLimit(1)
            }
        }
        .frame(width: tapTarget, height: tapTarget)
    }
}
