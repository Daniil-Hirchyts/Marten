import SwiftUI

struct MartenSwipeActionIcon: View {
    let systemName: String
    let backgroundColor: Color
    var foregroundColor: Color = .white

    var tapTarget: CGFloat = 28
    var visualSize: CGFloat = 24

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: visualSize, height: visualSize)
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(foregroundColor)
        }
        .frame(width: tapTarget, height: tapTarget)
    }
}
