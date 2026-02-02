import ClipboardCore
import SwiftUI

struct OverlayRootView: View {
    private let persistence: PersistenceController
    private let store: ClipItemStore

    init(persistence: PersistenceController, store: ClipItemStore) {
        self.persistence = persistence
        self.store = store
    }

    var body: some View {
        OverlayShellView(persistence: persistence, store: store)
    }
}
