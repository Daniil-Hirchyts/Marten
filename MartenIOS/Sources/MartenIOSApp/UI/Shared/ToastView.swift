import SwiftUI

struct ToastView: View {
    let message: String
    let systemImage: String?
    
    init(_ message: String, systemImage: String? = nil) {
        self.message = message
        self.systemImage = systemImage
    }
    
    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            Text(message)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.black.opacity(0.85))
                .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
        )
    }
}

@Observable
class ToastController {
    var message: String?
    var systemImage: String?
    var isShowing = false
    
    func show(_ message: String, systemImage: String? = nil, duration: TimeInterval = 2.0) {
        self.message = message
        self.systemImage = systemImage
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isShowing = true
        }
        
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                isShowing = false
            }
        }
    }
}

struct ToastModifier: ViewModifier {
    @Bindable var controller: ToastController
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if controller.isShowing, let message = controller.message {
                    ToastView(message, systemImage: controller.systemImage)
                        .padding(.top, 60)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1000)
                }
            }
    }
}

extension View {
    func toast(controller: ToastController) -> some View {
        modifier(ToastModifier(controller: controller))
    }
}
