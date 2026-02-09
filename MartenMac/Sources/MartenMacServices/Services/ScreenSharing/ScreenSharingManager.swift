import Combine

public final class ScreenSharingManager: ObservableObject {
    @Published public var isScreenSharingModeActive: Bool = false
    private let settings: any ScreenSharingSettingsProviding

    public init(
        settings: any ScreenSharingSettingsProviding = UserDefaultsScreenSharingSettingsProvider()
    ) {
        self.settings = settings
    }

    public var shouldShowOverlay: Bool {
        settings.showDuringScreenSharing() || !isScreenSharingModeActive
    }

    public func toggle() {
        isScreenSharingModeActive.toggle()
    }

    public func activate() {
        isScreenSharingModeActive = true
    }

    public func deactivate() {
        isScreenSharingModeActive = false
    }

    public var showDuringScreenSharingPreference: Bool {
        get { settings.showDuringScreenSharing() }
        set { settings.setShowDuringScreenSharing(newValue) }
    }
}
