import MartenCore
import SwiftUI

@MainActor
public struct MartenWatchRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var bootstrap: MartenWatchBootstrap

    public init() {
        _bootstrap = State(
            initialValue: MartenWatchStorageConfiguration().makeBootstrap()
        )
    }

    init(bootstrap: MartenWatchBootstrap) {
        _bootstrap = State(initialValue: bootstrap)
    }

    public var body: some View {
        NavigationStack {
            MartenWatchDashboardView(container: bootstrap.container)
        }
        .environment(\.managedObjectContext, bootstrap.persistenceController.viewContext)
        .task {
            await bootstrap.container.start()
        }
        .onChange(of: scenePhase) { _, newPhase in
            Task {
                await bootstrap.container.handleScenePhase(newPhase)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: MartenWatchNotifications.cloudKitRemoteChangeReceived)) { _ in
            Task {
                await bootstrap.container.handleCloudKitPushNotification()
            }
        }
    }
}

#Preview {
    MartenWatchRootView()
}
