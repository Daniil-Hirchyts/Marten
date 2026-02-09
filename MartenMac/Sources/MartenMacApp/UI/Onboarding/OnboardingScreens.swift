import AppKit
import MartenMacServices
import SwiftUI

struct WelcomeScreen: View {
    let onContinue: () -> Void
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 20) {
                appIcon
                    .frame(width: 140, height: 140)
                    .clipShape(.rect(cornerRadius: 32, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
                    .frame(width: 200, height: 200)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Instant clipboard memory")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Marten tracks what you copy, keeps history searchable, and lets you paste back with one shortcut.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            OnboardingCard {
                VStack(alignment: .leading, spacing: 12) {
                    OnboardingFeatureRow(
                        symbol: "rectangle.stack.fill",
                        title: "Unlimited history",
                        subtitle: "Access everything you copied in one place."
                    )
                    OnboardingFeatureRow(
                        symbol: "magnifyingglass.circle.fill",
                        title: "Fast search",
                        subtitle: "Find snippets by text, app, or content type."
                    )
                    OnboardingFeatureRow(
                        symbol: "command.square.fill",
                        title: "Global shortcut",
                        subtitle: "Use Cmd+Shift+V from any app."
                    )
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button {
                    onContinue()
                } label: {
                    Label("Start Setup", systemImage: "arrow.right")
                        .frame(minWidth: 160)
                }
                .onboardingPrimaryButtonStyle()
                .controlSize(.large)
                .accessibilityIdentifier("onboarding.button.welcome.continue")
                .accessibilityLabel("Continue to Permissions")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.step.welcome")
        .accessibilityLabel("Welcome Step")
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon = NSApp.applicationIconImage {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "doc.on.clipboard.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .padding(26)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }
}

struct PermissionsScreen: View {
    @ObservedObject var permissionManager: PermissionManager
    let onContinue: () -> Void
    let onBack: () -> Void

    private var allRequiredGranted: Bool {
        permissionManager.hasAccessibility && permissionManager.hasInputMonitoring
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Marten requires these permissions to operate correctly:")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            PermissionRequirementCard(
                title: "Accessibility",
                description: "Needed to paste content into other apps and support automation.",
                isGranted: permissionManager.hasAccessibility,
                actionAccessibilityIdentifier: "onboarding.button.permissions.accessibility",
                action: requestAccessibility
            )

            PermissionRequirementCard(
                title: "Input Monitoring",
                description: "Needed for global shortcuts to open Marten from anywhere.",
                isGranted: permissionManager.hasInputMonitoring,
                actionAccessibilityIdentifier: "onboarding.button.permissions.inputMonitoring",
                action: requestInputMonitoring
            )

            OnboardingCard {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "text.viewfinder")
                        .foregroundStyle(.secondary)
                    Text("Optional: enable Screen Recording to use OCR capture.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Settings") {
                        permissionManager.requestScreenRecordingSettings()
                    }
                    .onboardingSecondaryButtonStyle()
                    .controlSize(.small)
                    .accessibilityIdentifier("onboarding.button.permissions.screenRecording")
                }
            }

            if allRequiredGranted {
                Label("All required permissions are granted.", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("onboarding.permissions.status.granted")
                    .accessibilityLabel("Required Permissions Granted")
            } else {
                Label(
                    "Grant both permissions to unlock Marten.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.orange)
            }

            Spacer(minLength: 0)

            HStack {
                Button {
                    onBack()
                } label: {
                    Label("Back", systemImage: "arrow.left")
                }
                .onboardingSecondaryButtonStyle()
                .controlSize(.large)
                .accessibilityIdentifier("onboarding.button.permissions.back")

                Spacer()

                Button {
                    onContinue()
                } label: {
                    Label("Continue", systemImage: "arrow.right")
                        .frame(minWidth: 160)
                }
                .onboardingPrimaryButtonStyle()
                .controlSize(.large)
                .disabled(!allRequiredGranted)
                .accessibilityIdentifier("onboarding.button.permissions.continue")
                .accessibilityLabel("Continue to How To Use")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.step.permissions")
        .accessibilityLabel("Permissions Step")
    }

    private func requestAccessibility() {
        permissionManager.requestAccessibility()
        permissionManager.refresh()
    }

    private func requestInputMonitoring() {
        permissionManager.requestInputMonitoring()
        permissionManager.refresh()
    }
}

struct HowToUseScreen: View {
    let onContinue: () -> Void
    let onBack: () -> Void
    @State private var reveal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Use Marten in three quick steps:")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            OnboardingCard {
                VStack(alignment: .leading, spacing: 16) {
                    HowToStepRow(
                        number: 1,
                        title: "Copy anything",
                        subtitle: "Text, links, files, or images are captured automatically.",
                        isVisible: reveal,
                        delay: 0.0
                    )
                    HowToStepRow(
                        number: 2,
                        title: "Open Marten",
                        subtitle: "Press Cmd+Shift+V from any app.",
                        isVisible: reveal,
                        delay: 0.12
                    )
                    HowToStepRow(
                        number: 3,
                        title: "Select and paste",
                        subtitle: "Search, choose an item, and paste it instantly.",
                        isVisible: reveal,
                        delay: 0.24
                    )
                }
            }

            OnboardingCard {
                HStack(spacing: 16) {
                    Label("Main Shortcut", systemImage: "command")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text("Cmd")
                        .onboardingKeycap()
                    Text("+")
                        .foregroundStyle(.secondary)
                    Text("Shift")
                        .onboardingKeycap()
                    Text("+")
                        .foregroundStyle(.secondary)
                    Text("V")
                        .onboardingKeycap()
                }
            }

            OnboardingCard {
                Label("Tip: hold Shift while pasting to force plain text.", systemImage: "lightbulb.max.fill")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack {
                Button {
                    onBack()
                } label: {
                    Label("Back", systemImage: "arrow.left")
                }
                .onboardingSecondaryButtonStyle()
                .controlSize(.large)
                .accessibilityIdentifier("onboarding.button.howToUse.back")

                Spacer()

                Button {
                    onContinue()
                } label: {
                    Label("Continue", systemImage: "arrow.right")
                        .frame(minWidth: 160)
                }
                .onboardingPrimaryButtonStyle()
                .controlSize(.large)
                .accessibilityIdentifier("onboarding.button.howToUse.continue")
                .accessibilityLabel("Continue to Complete")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.84)) {
                reveal = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.step.howToUse")
        .accessibilityLabel("How To Use Step")
    }
}

struct CompleteScreen: View {
    @ObservedObject var permissionManager: PermissionManager
    let onContinue: () -> Void
    let onBackToPermissions: () -> Void
    @State private var animateStatus = false

    private var allRequiredGranted: Bool {
        permissionManager.hasAccessibility && permissionManager.hasInputMonitoring
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: allRequiredGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(allRequiredGranted ? .green : .orange)
                    .scaleEffect(animateStatus ? 1.06 : 0.94)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: animateStatus)

                VStack(alignment: .leading, spacing: 4) {
                    Text(allRequiredGranted ? "Setup Complete" : "Setup Incomplete")
                        .font(.system(size: 24, weight: .bold, design: .rounded))

                    Text(
                        allRequiredGranted
                            ? "Marten is ready. Launch the app experience."
                            : "Required permissions are missing. Return to activate them."
                    )
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                }
            }

            OnboardingCard {
                VStack(alignment: .leading, spacing: 10) {
                    PermissionSummaryRow(
                        title: "Accessibility",
                        isGranted: permissionManager.hasAccessibility
                    )
                    PermissionSummaryRow(
                        title: "Input Monitoring",
                        isGranted: permissionManager.hasInputMonitoring
                    )
                }
            }

            OnboardingCard {
                VStack(alignment: .leading, spacing: 10) {
                    NextStepRow(
                        symbol: "command",
                        text: "Open Marten anytime with Cmd+Shift+V."
                    )
                    NextStepRow(
                        symbol: "menubar.rectangle",
                        text: "Marten runs from the menu bar and starts capturing immediately."
                    )
                }
            }

            Spacer(minLength: 0)

            HStack {
                if allRequiredGranted {
                    Spacer()
                } else {
                    Button {
                        onBackToPermissions()
                    } label: {
                        Label("Back to Required Settings", systemImage: "arrow.uturn.left")
                    }
                    .onboardingSecondaryButtonStyle()
                    .controlSize(.large)
                    .accessibilityIdentifier("onboarding.button.complete.backToPermissions")

                    Spacer()
                }

                Button {
                    onContinue()
                } label: {
                    Label("Get Started", systemImage: "sparkles")
                        .frame(minWidth: 180)
                }
                .onboardingPrimaryButtonStyle()
                .controlSize(.large)
                .disabled(!allRequiredGranted)
                .accessibilityIdentifier("onboarding.button.complete.getStarted")
                .accessibilityLabel("Finish Onboarding")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            animateStatus = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.step.complete")
        .accessibilityLabel("Complete Step")
    }
}

private struct OnboardingFeatureRow: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 24, height: 24)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PermissionRequirementCard: View {
    let title: String
    let description: String
    let isGranted: Bool
    let actionAccessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        OnboardingCard {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: isGranted ? "checkmark.seal.fill" : "shield.lefthalf.filled")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isGranted ? .green : .orange)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(description)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isGranted {
                    PermissionStatusChip(title: "Granted")
                } else {
                    Button("Open Settings") {
                        action()
                    }
                    .onboardingSecondaryButtonStyle()
                    .controlSize(.regular)
                    .accessibilityIdentifier(actionAccessibilityIdentifier)
                }
            }
        }
    }
}

private struct HowToStepRow: View {
    let number: Int
    let title: String
    let subtitle: String
    let isVisible: Bool
    let delay: Double

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(.regularMaterial)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 12)
        .animation(
            .spring(response: 0.55, dampingFraction: 0.84).delay(delay),
            value: isVisible
        )
    }
}

private struct PermissionSummaryRow: View {
    let title: String
    let isGranted: Bool

    var body: some View {
        HStack {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isGranted ? .green : .orange)
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Spacer()
            Text(isGranted ? "Granted" : "Missing")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(isGranted ? .green : .orange)
        }
    }
}

private struct PermissionStatusChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(.green)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.green.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.green.opacity(0.35), lineWidth: 1)
            )
    }
}

private struct NextStepRow: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.blue)
                .frame(width: 16, height: 16)
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

private struct OnboardingCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            )
    }
}

private extension View {
    func onboardingPrimaryButtonStyle() -> some View {
        self
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.11, green: 0.49, blue: 0.95))
    }

    func onboardingSecondaryButtonStyle() -> some View {
        self.buttonStyle(.bordered)
    }

    func onboardingKeycap() -> some View {
        self
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            )
    }
}
