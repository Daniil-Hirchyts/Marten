import ClipboardMacServices
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case permissions
    case howToUse
    case complete

    var title: String {
        switch self {
        case .welcome:
            return "Welcome to Paste"
        case .permissions:
            return "Activate Required Permissions"
        case .howToUse:
            return "How It Works"
        case .complete:
            return "Ready to Launch"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:
            return "A fast clipboard workflow built for macOS."
        case .permissions:
            return "Paste requires these settings to work reliably."
        case .howToUse:
            return "Your shortcuts and daily workflow in one place."
        case .complete:
            return "Confirm setup and continue to the app."
        }
    }
}

struct OnboardingFlow: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @ObservedObject private var permissionManager: PermissionManager
    @State private var currentStep: OnboardingStep = .welcome
    @State private var isForwardTransition = true
    @State private var hasEntered = false
    @Environment(\.dismiss) private var dismiss

    var onClose: (() -> Void)?

    init(permissionManager: PermissionManager, onClose: (() -> Void)? = nil) {
        self.permissionManager = permissionManager
        self.onClose = onClose
    }

    private var totalSteps: Int {
        OnboardingStep.allCases.count
    }

    private var requiredPermissionsGranted: Bool {
        permissionManager.hasAccessibility && permissionManager.hasInputMonitoring
    }

    var body: some View {
        ZStack {
            OnboardingAnimatedBackdrop()
                .clipShape(.rect(cornerRadius: 30, style: .continuous))

            VStack(spacing: 0) {
                // Fixed Header Area
                OnboardingProgressHeader(
                    currentStep: currentStep,
                    totalSteps: totalSteps
                )
                .padding(.horizontal, 32)
                .padding(.top, 32)
                .padding(.bottom, 24)
                .background(Color.clear) // Ensure touch doesn't pass through if needed, though not interactive

                // Fixed Content Area
                ZStack {
                    stepView
                        .id(currentStep)
                        .transition(stepTransition)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
                .clipped()
            }
        }
        .frame(width: 850, height: 650)
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 30, style: .continuous))
        .scaleEffect(hasEntered ? 1 : 0.98)
        .opacity(hasEntered ? 1 : 0)
        .animation(.spring(response: 0.6, dampingFraction: 0.86), value: hasEntered)
        .onAppear {
            permissionManager.refresh()
            hasEntered = true
        }
        .task {
            await monitorPermissions()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.flow")
    }

    @ViewBuilder
    private var stepView: some View {
        switch currentStep {
        case .welcome:
            WelcomeScreen(onContinue: advance)
        case .permissions:
            PermissionsScreen(
                permissionManager: permissionManager,
                onContinue: advance,
                onBack: goBack
            )
        case .howToUse:
            HowToUseScreen(
                onContinue: advance,
                onBack: goBack
            )
        case .complete:
            CompleteScreen(
                permissionManager: permissionManager,
                onContinue: completeOnboarding,
                onBackToPermissions: jumpToPermissions
            )
        }
    }

    private var stepTransition: AnyTransition {
        let insertionEdge: Edge = isForwardTransition ? .trailing : .leading
        let removalEdge: Edge = isForwardTransition ? .leading : .trailing

        return .asymmetric(
            insertion: .move(edge: insertionEdge)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.98)),
            removal: .move(edge: removalEdge)
                .combined(with: .opacity)
        )
    }

    private func advance() {
        switch currentStep {
        case .welcome:
            move(to: .permissions, forward: true)
        case .permissions:
            guard requiredPermissionsGranted else { return }
            move(to: .howToUse, forward: true)
        case .howToUse:
            move(to: .complete, forward: true)
        case .complete:
            completeOnboarding()
        }
    }

    private func goBack() {
        switch currentStep {
        case .welcome:
            return
        case .permissions:
            move(to: .welcome, forward: false)
        case .howToUse:
            move(to: .permissions, forward: false)
        case .complete:
            move(to: .howToUse, forward: false)
        }
    }

    private func jumpToPermissions() {
        move(to: .permissions, forward: false)
    }

    private func move(to step: OnboardingStep, forward: Bool) {
        guard step != currentStep else { return }
        isForwardTransition = forward
        withAnimation(.spring(response: 0.52, dampingFraction: 0.86)) {
            currentStep = step
        }
    }

    private func completeOnboarding() {
        guard requiredPermissionsGranted else {
            move(to: .permissions, forward: false)
            return
        }

        hasCompletedOnboarding = true
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func monitorPermissions() async {
        while !Task.isCancelled {
            await MainActor.run {
                permissionManager.refresh()
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
    }
}

private struct OnboardingProgressHeader: View {
    let currentStep: OnboardingStep
    let totalSteps: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentStep.title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(height: 36, alignment: .leading)

                    Text(currentStep.subtitle)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(height: 20, alignment: .leading)
                }
                .frame(height: 60, alignment: .topLeading)

                Spacer()

                Text("Step \(currentStep.rawValue + 1) of \(totalSteps)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                    )
            }
            .frame(height: 60, alignment: .top)

            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                    Capsule()
                        .fill(step.rawValue <= currentStep.rawValue ? Color.blue : Color.primary.opacity(0.1))
                        .frame(height: 6)
                        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: currentStep)
                }
            }
        }
    }
}

private struct OnboardingAnimatedBackdrop: View {
    @State private var animate = false
    @Environment(\.colorScheme) private var colorScheme

    private var gradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.08, green: 0.10, blue: 0.16),
                Color(red: 0.12, green: 0.14, blue: 0.24),
                Color(red: 0.05, green: 0.08, blue: 0.14)
            ]
        } else {
            return [
                Color(red: 0.85, green: 0.90, blue: 0.95),
                Color(red: 0.80, green: 0.88, blue: 0.93),
                Color(red: 0.86, green: 0.86, blue: 0.93)
            ]
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: gradientColors,
                startPoint: animate ? .topLeading : .bottomLeading,
                endPoint: animate ? .bottomTrailing : .topTrailing
            )

            Circle()
                .fill(Color.cyan.opacity(colorScheme == .dark ? 0.08 : 0.12))
                .frame(width: 320, height: 320)
                .blur(radius: 52)
                .offset(
                    x: animate ? -220 : 120,
                    y: animate ? -140 : 110
                )

            Circle()
                .fill(Color.blue.opacity(colorScheme == .dark ? 0.1 : 0.1))
                .frame(width: 280, height: 280)
                .blur(radius: 48)
                .offset(
                    x: animate ? 180 : -200,
                    y: animate ? 150 : -120
                )
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 12).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}
