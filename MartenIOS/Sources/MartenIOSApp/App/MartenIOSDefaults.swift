import Foundation
import MartenCore
import SwiftUI

public enum MartenIOSDefaults {
    public static let syncEnabledKey = "com.hirchyts.marten.syncEnabled"
    public static let appearanceKey = "marten.ios.appearance"
    public static let lockHookPinboardIDsKey = "marten.ios.pinboard.lockedIDs"
    public static let selectedPinboardIDKey = "marten.ios.dashboard.selectedPinboardID"
    public static let showClipboardHistoryLabelKey = "marten.ios.dashboard.showClipboardHistoryLabel"
    public static let generateLinkPreviewsKey = "generateLinkPreviews"
    public static let ignoreConfidentialContentKey = "ignoreConfidentialContent"
    public static let ignoreTransientContentKey = "ignoreTransientContent"
    public static let keyboardLastSeenAtKey = "marten.keyboard.lastSeenAt"
    public static let keyboardLastMutationAtKey = "marten.keyboard.lastMutationAt"
    public static let shareExtensionLastSuccessAtKey = "marten.shareExtension.lastSuccessAt"
    public static let showIntegrationsOnboardingKey = "marten.ios.integrations.showOnboarding"
    public static let lastPasteboardChangeCountKey = "marten.ios.pasteboard.lastChangeCount"

    public static func registerDefaults(_ userDefaults: UserDefaults = .standard) {
        userDefaults.register(defaults: [
            syncEnabledKey: false,
            appearanceKey: MartenIOSAppearance.system.rawValue,
            lockHookPinboardIDsKey: [String](),
            selectedPinboardIDKey: "",
            showClipboardHistoryLabelKey: true,
            generateLinkPreviewsKey: true, // Changed to true by default
            ignoreConfidentialContentKey: true,
            ignoreTransientContentKey: true,
            keyboardLastSeenAtKey: 0.0,
            keyboardLastMutationAtKey: 0.0,
            shareExtensionLastSuccessAtKey: 0.0,
            showIntegrationsOnboardingKey: true,
            lastPasteboardChangeCountKey: 0,
        ])
        SharedPinboardsFeatureFlag.registerDefaults(userDefaults)
    }
}

public enum MartenIOSAppearance: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    public var displayName: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    public var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}
