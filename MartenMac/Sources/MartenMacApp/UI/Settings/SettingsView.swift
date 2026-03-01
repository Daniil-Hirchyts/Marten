import MartenCore
import SwiftUI

// MARK: - Animated Backdrop

private struct SettingsAnimatedBackdrop: View {
    @State private var animate = false
    @Environment(\.colorScheme) private var colorScheme

    private var gradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.08, green: 0.10, blue: 0.16),
                Color(red: 0.12, green: 0.14, blue: 0.24),
                Color(red: 0.05, green: 0.08, blue: 0.14),
            ]
        } else {
            return [
                Color(red: 0.85, green: 0.90, blue: 0.95),
                Color(red: 0.80, green: 0.88, blue: 0.93),
                Color(red: 0.86, green: 0.86, blue: 0.93),
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
                .fill(Color.cyan.opacity(colorScheme == .dark ? 0.03 : 0.04))
                .frame(width: 320, height: 320)
                .blur(radius: 52)
                .offset(
                    x: animate ? -220 : 120,
                    y: animate ? -140 : 110
                )

            Circle()
                .fill(Color.blue.opacity(colorScheme == .dark ? 0.04 : 0.04))
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

// MARK: - Settings Tab Enum

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case shortcuts
    case privacy
    case account
    case subscription

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .shortcuts: return "Shortcuts"
        case .privacy: return "Privacy"
        case .account: return "Account"
        case .subscription: return "Subscription"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .shortcuts: return "keyboard"
        case .privacy: return "hand.raised"
        case .account: return "person.crop.circle"
        case .subscription: return "creditcard"
        }
    }

    var description: String {
        switch self {
        case .general: return "Startup and behavior"
        case .shortcuts: return "Keyboard shortcuts"
        case .privacy: return "Security and filtering"
        case .account: return "iCloud sync"
        case .subscription: return "Manage plan"
        }
    }
}

// MARK: - Main Settings View

struct SettingsView: View {
    var syncCoordinator: SyncCoordinator?

    @State private var selectedTab: SettingsTab? = .general

    init(syncCoordinator: SyncCoordinator? = nil, initialTab: SettingsTab? = .general) {
        self.syncCoordinator = syncCoordinator
        self._selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Label {
                        Text(tab.title)
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                    } icon: {
                        Image(systemName: tab.icon)
                    }
                    .tag(tab)

                }
            }
            .listStyle(.sidebar)
            .background(.regularMaterial)
            .scrollContentBackground(.hidden)
        } detail: {
            ScrollView {
                Group {
                    switch currentTab {
                    case .general:
                        GeneralSettingsContent(syncCoordinator: syncCoordinator)
                    case .shortcuts:
                        ShortcutsSettingsContent()
                    case .privacy:
                        PrivacySettingsContent()
                    case .account:
                        if let syncCoordinator {
                            AccountSettingsContent(syncCoordinator: syncCoordinator)
                        } else {
                            AccountUnavailableContent()
                        }
                    case .subscription:
                        SubscriptionSettingsContent()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SettingsAnimatedBackdrop().ignoresSafeArea())
            .navigationTitle(currentTab.title)
            .background(ScrollViewAppearanceConfigurator())

        }
        .frame(maxWidth: 800, maxHeight: 600)
    }

    private var currentTab: SettingsTab {
        selectedTab ?? .general
    }
}

// MARK: - Settings Card Component

struct SettingsCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Settings Section Header

struct SettingsSectionHeader: View {
    let title: String
    let icon: String?

    init(_ title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.leading, 4)
        .padding(.bottom, 6)
        .padding(.top, 8)
    }
}

// MARK: - Scroll View Appearance Configurator

private struct ScrollViewAppearanceConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configureScrollView(from: view, remainingAttempts: 8)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureScrollView(from: nsView, remainingAttempts: 8)
    }

    private func configureScrollView(from view: NSView, remainingAttempts: Int) {
        if let scrollView = findScrollView(from: view) {
            if let scroller = scrollView.verticalScroller {
                scroller.controlSize = .mini
            }
            return
        }

        guard remainingAttempts > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            configureScrollView(from: view, remainingAttempts: remainingAttempts - 1)
        }
    }

    private func findScrollView(from view: NSView) -> NSScrollView? {
        if let enclosing = view.enclosingScrollView {
            return enclosing
        }

        var current = view.superview
        while let node = current {
            if let scroll = node as? NSScrollView {
                return scroll
            }
            current = node.superview
        }

        return nil
    }
}

// MARK: - Settings Toggle Row

struct SettingsToggleRow: View {
    let title: String
    let description: String?
    @Binding var isOn: Bool
    let identifier: String

    init(_ title: String, description: String? = nil, isOn: Binding<Bool>, identifier: String) {
        self.title = title
        self.description = description
        self._isOn = isOn
        self.identifier = identifier
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)

                if let description {
                    Text(description)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityIdentifier(identifier)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Account Unavailable Content

private struct AccountUnavailableContent: View {
    var body: some View {
        VStack(spacing: 20) {
            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.icloud")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("iCloud Sync Unavailable")
                                .font(.system(size: 15, weight: .semibold))
                            Text("This build is not signed with iCloud entitlements.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("Run the signed app bundle to enable iCloud sync.")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
