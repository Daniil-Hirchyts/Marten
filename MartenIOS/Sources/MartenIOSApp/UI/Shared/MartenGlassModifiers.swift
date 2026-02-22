import SwiftUI

// MARK: - Shimmer Modifier

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.12), .clear],
                    startPoint: .init(x: phase - 0.5, y: 0.5),
                    endPoint: .init(x: phase + 0.5, y: 0.5)
                )
                .blendMode(.overlay)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: .capsule)
    }
}

// MARK: - View Extensions

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }

    @ViewBuilder
    func glassSearchBackground() -> some View {
        #if os(iOS)
            if #available(iOS 26, *) {
                self
                    .background(Capsule().fill(Color.clear))
                    .glassEffect(.regular.interactive(), in: .capsule)
            } else {
                self.background(.regularMaterial, in: .capsule)
            }
        #else
            self.background(.regularMaterial, in: .capsule)
        #endif
    }

    @ViewBuilder
    func glassChipBackground(isHighlighted: Bool) -> some View {
        #if os(iOS)
            if #available(iOS 26, *) {
                self
                    .background(Capsule().fill(Color.clear))
                    .glassEffect(
                        isHighlighted
                            ? .regular.tint(.accentColor).interactive()
                            : .regular.interactive(),
                        in: .capsule
                    )
            } else {
                self.background(
                    isHighlighted
                        ? Color.accentColor.opacity(0.18)
                        : Color.secondary.opacity(0.12),
                    in: .capsule
                )
            }
        #else
            self.background(
                isHighlighted
                    ? Color.accentColor.opacity(0.18)
                    : Color.secondary.opacity(0.12),
                in: .capsule
            )
        #endif
    }

    @ViewBuilder
    func glassCircleBackground(isHighlighted: Bool) -> some View {
        #if os(iOS)
            if #available(iOS 26, *) {
                self
                    .background(Circle().fill(Color.clear))
                    .glassEffect(
                        isHighlighted
                            ? .regular.tint(.accentColor).interactive()
                            : .regular.interactive(),
                        in: .circle
                    )
            } else {
                self.background(
                    Circle()
                        .fill(
                            isHighlighted
                                ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.14))
                )
            }
        #else
            self.background(
                Circle()
                    .fill(
                        isHighlighted
                            ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.14))
            )
        #endif
    }
}
