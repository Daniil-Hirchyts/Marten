import CoreData
import MartenCore
import SwiftUI
#if canImport(CloudKit)
import CloudKit
#endif

@MainActor
@Observable
public final class MartenIOSBootstrap {
    public let persistenceController: PersistenceController
    public let container: MartenIOSAppContainer

    public init(
        persistenceController: PersistenceController = .shared,
        container: MartenIOSAppContainer? = nil
    ) {
        self.persistenceController = persistenceController
        self.container = container ?? MartenIOSAppContainer(persistenceController: persistenceController)
    }
}

@MainActor
public struct MartenIOSRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var bootstrap: MartenIOSBootstrap

    public init() {
        _bootstrap = State(initialValue: MartenIOSBootstrap())
    }

    public init(bootstrap: MartenIOSBootstrap) {
        _bootstrap = State(initialValue: bootstrap)
    }

    public var body: some View {
        MartenIOSShellView(container: bootstrap.container)
            .environment(\.managedObjectContext, bootstrap.persistenceController.viewContext)
            .preferredColorScheme(bootstrap.container.preferredColorScheme)
            .task {
                await bootstrap.container.start()
            }
            .onChange(of: scenePhase) { _, newPhase in
                Task {
                    await bootstrap.container.handleScenePhase(newPhase)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: MartenIOSNotifications.cloudKitShareAccepted)) { notification in
                #if canImport(CloudKit)
                guard let metadata = notification.object as? CKShare.Metadata else { return }
                Task {
                    await bootstrap.container.acceptShare(metadata: metadata)
                }
                #endif
            }
            .onOpenURL { url in
                bootstrap.container.handleDeepLink(url)
            }
    }
}

#Preview {
    let persistence = PersistenceController(inMemory: true)
    let bootstrap = MartenIOSBootstrap(persistenceController: persistence)
    return MartenIOSRootView(bootstrap: bootstrap)
}
