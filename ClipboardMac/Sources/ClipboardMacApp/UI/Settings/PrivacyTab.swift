import AppKit
import SwiftUI

struct PrivacyTab: View {
    @AppStorage("showDuringScreenSharing") private var showDuringScreenSharing = true
    @AppStorage("generateLinkPreviews") private var generateLinkPreviews = false
    @AppStorage("ignoreConfidentialContent") private var ignoreConfidentialContent = true
    @AppStorage("ignoreTransientContent") private var ignoreTransientContent = true

    @StateObject private var ignoredAppsModel = IgnoredAppsViewModel()
    @State private var selectedIgnoredBundleID: String?

    var body: some View {
        Form {
            Section("Visibility") {
                Toggle("Show during screen sharing", isOn: $showDuringScreenSharing)
                    .accessibilityIdentifier("settings.toggle.showDuringScreenSharing")
                    .accessibilityLabel("Show during screen sharing")
            }

            Section("Content Filtering") {
                VStack(alignment: .leading) {
                    Toggle("Generate link previews", isOn: $generateLinkPreviews)
                        .accessibilityIdentifier("settings.toggle.generateLinkPreviews")
                        .accessibilityLabel("Generate link previews")
                    Text("When enabled, Paste fetches metadata from websites you copy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading) {
                    Toggle("Ignore confidential content", isOn: $ignoreConfidentialContent)
                        .accessibilityIdentifier("settings.toggle.ignoreConfidentialContent")
                        .accessibilityLabel("Ignore confidential content")
                    Text("Automatically filters passwords, credit cards, and API keys.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Ignore transient content", isOn: $ignoreTransientContent)
                    .accessibilityIdentifier("settings.toggle.ignoreTransientContent")
                    .accessibilityLabel("Ignore transient content")
            }

            Section("Ignored Applications") {
                List(selection: $selectedIgnoredBundleID) {
                    ForEach(ignoredAppsModel.apps) { app in
                        HStack(spacing: 8) {
                            if let data = app.iconData, let icon = NSImage(data: data) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 16, height: 16)
                            }
                            Text(app.name)
                            Spacer()
                        }
                        .tag(app.bundleIdentifier)
                    }
                }
                .onAppear {
                    ignoredAppsModel.refresh()
                }
                .listStyle(.inset)
                .frame(height: 150)
                .background(Color.clear)
                .accessibilityIdentifier("settings.list.ignoredApps")
                .accessibilityLabel("Ignored applications")
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )

                HStack {
                    Button {
                        ignoredAppsModel.addFromOpenPanel()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("settings.button.ignoredApps.add")
                    .accessibilityLabel("Add ignored application")

                    Button {
                        if let selectedIgnoredBundleID {
                            ignoredAppsModel.remove(bundleIdentifier: selectedIgnoredBundleID)
                            self.selectedIgnoredBundleID = nil
                        }
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selectedIgnoredBundleID == nil)
                    .accessibilityIdentifier("settings.button.ignoredApps.remove")
                    .accessibilityLabel("Remove ignored application")

                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
