import SwiftUI
import AppKit
import ApplicationServices

struct WelcomeScreen: View {
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 128, height: 128)
            } else {
                // Fallback if icon is missing (e.g. preview)
                Image(systemName: "doc.on.clipboard")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 128)
                    .foregroundColor(.accentColor)
            }
            
            Text("Welcome to Paste")
                .font(.largeTitle)
                .bold()
            
            Text("Your clipboard history manager for macOS")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button("Continue") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("onboarding.button.welcome.continue")
            .accessibilityLabel("Continue to Permissions")
        }
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.step.welcome")
        .accessibilityLabel("Welcome Step")
    }
}

struct PermissionsScreen: View {
    let onContinue: () -> Void
    @State private var hasPermission = false
    
    // Timer to periodically check permission status while the window is open
    let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.raised.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .foregroundColor(.blue)
            
            Text("Accessibility Permission Required")
                .font(.title)
                .bold()
            
            Text("Paste needs Accessibility permission to monitor your clipboard and paste content into apps.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            Spacer()
            
            if hasPermission {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Permission Granted")
                        .font(.headline)
                }
                .padding(.bottom, 10)
                .accessibilityIdentifier("onboarding.permissions.status.granted")
                .accessibilityLabel("Accessibility Permission Granted")
                
                Button("Continue") {
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("onboarding.button.permissions.continue")
                .accessibilityLabel("Continue to How To Use")
            } else {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("onboarding.button.permissions.openSettings")
                .accessibilityLabel("Open Accessibility System Settings")
                
                Button("Skip for Now") {
                    onContinue()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .accessibilityIdentifier("onboarding.button.permissions.skip")
                .accessibilityLabel("Skip Accessibility Permission")
            }
        }
        .padding()
        .onAppear {
            checkPermission()
        }
        .onReceive(timer) { _ in
            checkPermission()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.step.permissions")
        .accessibilityLabel("Permissions Step")
    }
    
    private func checkPermission() {
        let trusted = AXIsProcessTrusted()
        if trusted != hasPermission {
            withAnimation {
                hasPermission = trusted
            }
        }
    }
}

struct HowToUseScreen: View {
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "keyboard.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .foregroundColor(.accentColor)
            
            Text("Press Cmd+Shift+V to open Paste")
                .font(.title)
                .bold()
                .multilineTextAlignment(.center)
            
            Text("Browse your clipboard history, search, and paste with one click.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            Spacer()
            
            Button("Continue") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("onboarding.button.howToUse.continue")
            .accessibilityLabel("Continue to Complete")
        }
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.step.howToUse")
        .accessibilityLabel("How To Use Step")
    }
}

struct CompleteScreen: View {
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .foregroundColor(.green)
            
            Text("You're All Set!")
                .font(.title)
                .bold()
            
            Text("Start copying and Paste will remember everything.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button("Get Started") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("onboarding.button.complete.getStarted")
            .accessibilityLabel("Finish Onboarding")
        }
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.step.complete")
        .accessibilityLabel("Complete Step")
    }
}
