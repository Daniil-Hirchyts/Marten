import AppKit
import ClipboardCore
import SwiftUI

struct PrivacySettingsContent: View {
    @AppStorage("showDuringScreenSharing") private var showDuringScreenSharing = true
    @AppStorage("generateLinkPreviews") private var generateLinkPreviews = false
    @AppStorage("ignoreConfidentialContent") private var ignoreConfidentialContent = true
    @AppStorage("ignoreTransientContent") private var ignoreTransientContent = true

    @StateObject private var ignoredAppsModel = IgnoredAppsViewModel()
    @State private var selectedIgnoredBundleID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Visibility Section
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeader("Visibility", icon: "eye")

                SettingsCard {
                    SettingsToggleRow(
                        "Show during screen sharing",
                        description: "Keep overlay visible when sharing your screen",
                        isOn: $showDuringScreenSharing,
                        identifier: "settings.toggle.showDuringScreenSharing"
                    )
                }
            }

            // Content Filtering Section
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeader("Content Filtering", icon: "line.3.horizontal.decrease.circle")

                SettingsCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsToggleRow(
                            "Generate link previews",
                            description: "Fetch metadata from websites you copy",
                            isOn: $generateLinkPreviews,
                            identifier: "settings.toggle.generateLinkPreviews"
                        )

                        Divider()
                            .background(Color.primary.opacity(0.1))

                        SettingsToggleRow(
                            "Ignore confidential content",
                            description: "Filter passwords, credit cards, and API keys",
                            isOn: $ignoreConfidentialContent,
                            identifier: "settings.toggle.ignoreConfidentialContent"
                        )

                        Divider()
                            .background(Color.primary.opacity(0.1))

                        SettingsToggleRow(
                            "Ignore transient content",
                            description: "Skip temporary clipboard content",
                            isOn: $ignoreTransientContent,
                            identifier: "settings.toggle.ignoreTransientContent"
                        )
                    }
                }
            }

            // Ignored Applications Section
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeader("Ignored Applications", icon: "app.badge.checkmark")

                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Content copied from these apps won't be saved")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        // App List
                        if ignoredAppsModel.apps.isEmpty {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    Image(systemName: "app.dashed")
                                        .font(.system(size: 24))
                                        .foregroundStyle(.tertiary)
                                    Text("No ignored apps")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 20)
                                Spacer()
                            }
                        } else {
                            VStack(spacing: 4) {
                                ForEach(ignoredAppsModel.apps) { app in
                                    IgnoredAppRow(
                                        app: app,
                                        isSelected: selectedIgnoredBundleID == app.bundleIdentifier,
                                        onSelect: {
                                            selectedIgnoredBundleID = app.bundleIdentifier
                                        }
                                    )
                                }
                            }
                        }

                        // Action Buttons
                        HStack(spacing: 8) {
                            Button {
                                ignoredAppsModel.addFromOpenPanel()
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(width: 12, height: 12)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .frame(width: 28, height: 22)
                            .accessibilityIdentifier("settings.button.ignoredApps.add")

                            Button {
                                if let selectedIgnoredBundleID {
                                    ignoredAppsModel.remove(bundleIdentifier: selectedIgnoredBundleID)
                                    self.selectedIgnoredBundleID = nil
                                }
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(width: 12, height: 12)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .frame(width: 28, height: 22)
                            .disabled(selectedIgnoredBundleID == nil)
                            .accessibilityIdentifier("settings.button.ignoredApps.remove")

                            Spacer()
                        }
                    }
                }
            }
        }
        .onAppear {
            ignoredAppsModel.refresh()
        }
    }
}

// MARK: - Ignored App Row

private struct IgnoredAppRow: View {
    let app: IgnoredApp
    let isSelected: Bool
    let onSelect: () -> Void

    private var appIcon: NSImage? {
        // Try to load from saved icon data first
        if let data = app.iconData, let icon = NSImage(data: data) {
            return icon
        }

        // Try to get icon from bundle identifier
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }

        return nil
    }

    var body: some View {
        HStack(spacing: 10) {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }

            Text(app.name)
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

// Keep the old tab for compatibility
struct PrivacyTab: View {
    var body: some View {
        PrivacySettingsContent()
            .padding()
    }
}
