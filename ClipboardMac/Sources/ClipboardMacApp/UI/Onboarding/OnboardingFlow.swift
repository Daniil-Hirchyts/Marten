import SwiftUI

enum OnboardingStep {
    case welcome
    case permissions
    case howToUse
    case complete
}

struct OnboardingFlow: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentStep: OnboardingStep = .welcome
    @Environment(\.dismiss) private var dismiss

    var onClose: (() -> Void)? = nil

    var body: some View {
        VStack {
            switch currentStep {
            case .welcome:
                WelcomeScreen(onContinue: advance)
                    .transition(.opacity)
            case .permissions:
                PermissionsScreen(onContinue: advance)
                    .transition(.opacity)
            case .howToUse:
                HowToUseScreen(onContinue: advance)
                    .transition(.opacity)
            case .complete:
                CompleteScreen(onContinue: completeOnboarding)
                    .transition(.opacity)
            }
        }
        .padding(40)
        .frame(width: 500, height: 400)
        // Make the window fixed size if presented as a window,
        // though usually constraints are handled by the window controller.
        // For SwiftUI WindowGroup, .windowResizability(.contentSize) is often used in the App struct.
    }

    private func advance() {
        withAnimation {
            switch currentStep {
            case .welcome:
                currentStep = .permissions
            case .permissions:
                currentStep = .howToUse
            case .howToUse:
                currentStep = .complete
            case .complete:
                completeOnboarding()
            }
        }
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}
