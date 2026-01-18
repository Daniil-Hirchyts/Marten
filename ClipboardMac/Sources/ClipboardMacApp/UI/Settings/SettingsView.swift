import ClipboardCore
import SwiftUI

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

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .listStyle(.sidebar)
        } detail: {
            ScrollView {
                Group {
                    switch currentTab {
                    case .general:
                        GeneralSettingsContent()
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
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(currentTab.title)
        }
        .toolbar(removing: .sidebarToggle)
        .frame(width: 720, height: 520)
    }

    private var currentTab: SettingsTab {
        selectedTab ?? .general
    }
}

// MARK: - Settings Card Component

struct SettingsCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
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
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .padding(.bottom, 8)
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
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $isOn) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityIdentifier(identifier)

            if let description {
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 2)
            }
        }
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
