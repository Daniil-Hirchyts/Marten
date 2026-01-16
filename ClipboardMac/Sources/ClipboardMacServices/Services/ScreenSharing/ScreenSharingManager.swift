import SwiftUI

public final class ScreenSharingManager: ObservableObject {
    @Published public var isScreenSharingModeActive: Bool = false
    @AppStorage("showDuringScreenSharing") private var showDuringScreenSharing: Bool = true

    public init() {}

    public var shouldShowOverlay: Bool {
        showDuringScreenSharing || !isScreenSharingModeActive
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
        get { showDuringScreenSharing }
        set { showDuringScreenSharing = newValue }
    }
}
