import ClipboardCore
import SwiftUI

struct OverlayRootView: View {
    private let persistence: PersistenceController
    private let dependencies: OverlayDependencies

    init(persistence: PersistenceController, dependencies: OverlayDependencies) {
        self.persistence = persistence
        self.dependencies = dependencies
    }

    var body: some View {
        OverlayShellView(persistence: persistence, dependencies: dependencies)
    }
}
