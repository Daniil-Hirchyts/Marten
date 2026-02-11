import SwiftUI

#if canImport(UIKit)
import UIKit

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
struct ActivityView: View {
    let activityItems: [Any]

    var body: some View {
        ContentUnavailableView(
            "Share Unavailable",
            systemImage: "square.and.arrow.up",
            description: Text("Sharing is only available on iOS in this build.")
        )
    }
}
#endif
