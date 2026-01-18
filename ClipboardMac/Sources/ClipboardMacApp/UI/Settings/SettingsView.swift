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

    @State private var selectedTab: SettingsTab = .general
    @State private var hoveredTab: SettingsTab?

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            sidebar
                .frame(width: 200)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1)

            // Content
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 720, height: 520)
        .background(SettingsBackgroundView())
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            Text("Settings")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 8)

            // Navigation Items
            ForEach(SettingsTab.allCases) { tab in
                SettingsSidebarItem(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    isHovered: hoveredTab == tab
                )
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedTab = tab
                    }
                }
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        hoveredTab = hovering ? tab : nil
                    }
                }
            }

            Spacer()

            // App Info
            VStack(alignment: .leading, spacing: 4) {
                Text("Paste")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                Text("Version 1.0.0")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Tab Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedTab.title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.primary)

                    Text(selectedTab.description)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

                // Tab Content
                Group {
                    switch selectedTab {
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
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }
}

// MARK: - Sidebar Item

private struct SettingsSidebarItem: View {
    let tab: SettingsTab
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tab.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(width: 20)

            Text(tab.title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(itemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 8)
        .accessibilityIdentifier("settings.sidebar.\(tab.rawValue)")
        .accessibilityLabel(tab.title)
        .accessibilityValue(isSelected ? "Selected" : "")
    }

    @ViewBuilder
    private var itemBackground: some View {
        if #available(macOS 26.0, *) {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.clear)
                    .glassStyle(shape: .roundedRectangle(cornerRadius: 8), isProminent: true)
            } else if isHovered {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            } else {
                Color.clear
            }
        } else {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(DesignTokens.Opacity.backgroundStrong))
            } else if isHovered {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(DesignTokens.Opacity.backgroundSubtle))
            } else {
                Color.clear
            }
        }
    }
}

// MARK: - Settings Background

private struct SettingsBackgroundView: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Rectangle()
                .fill(.ultraThinMaterial)
        } else {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        }
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.system(size: 12, weight: .semibold))
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
