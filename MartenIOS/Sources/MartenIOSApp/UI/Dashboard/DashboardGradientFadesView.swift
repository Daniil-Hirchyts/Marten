import SwiftUI

struct DashboardGradientFadesView: View {
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: Color(platformColor: .platformSystemBackground).opacity(1.0), location: 0.0),
                        .init(color: Color(platformColor: .platformSystemBackground).opacity(0.9), location: 0.2),
                        .init(color: Color(platformColor: .platformSystemBackground).opacity(0.5), location: 0.5),
                        .init(color: Color(platformColor: .platformSystemBackground).opacity(0.1), location: 0.8),
                        .init(color: Color(platformColor: .platformSystemBackground).opacity(0.0), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 140)
                .allowsHitTesting(false)
                Spacer()
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    stops: [
                        .init(color: Color(platformColor: .platformSystemBackground).opacity(0.0), location: 0.0),
                        .init(color: Color(platformColor: .platformSystemBackground).opacity(0.1), location: 0.2),
                        .init(color: Color(platformColor: .platformSystemBackground).opacity(0.5), location: 0.5),
                        .init(color: Color(platformColor: .platformSystemBackground).opacity(0.9), location: 0.8),
                        .init(color: Color(platformColor: .platformSystemBackground).opacity(1.0), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 140)
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()
        }
    }
}

