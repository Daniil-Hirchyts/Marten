import SwiftUI

struct TransparencyGrid: View {
    var squareSize: CGFloat = 8

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let light =
                (colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06))
            let dark =
                (colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12))

            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = 0
                var col = 0
                while x < size.width {
                    let color = ((row + col) % 2 == 0) ? light : dark
                    let rect = CGRect(x: x, y: y, width: squareSize, height: squareSize)
                    context.fill(Path(rect), with: .color(color))
                    x += squareSize
                    col += 1
                }
                y += squareSize
                row += 1
            }
        }
    }
}
