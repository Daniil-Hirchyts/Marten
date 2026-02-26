import SwiftUI

struct DashboardFadeMask: ViewModifier {
    func body(content: Content) -> some View {
        content
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.1), location: 0.0),
                            .init(color: .black.opacity(0.3), location: 0.6),
                            .init(color: .black.opacity(0.8), location: 0.8),
                            .init(color: .black, location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 140)

                    Rectangle().fill(.black)

                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .black.opacity(0.9), location: 0.2),
                            .init(color: .black.opacity(0.5), location: 0.5),
                            .init(color: .black.opacity(0.1), location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                }
                .ignoresSafeArea()
            )
    }
}
