import Combine
import MartenCore
import MartenIOSApp
import SwiftUI
import UIKit

fileprivate final class ShareExtensionState: ObservableObject {
    @Published var payloadCount = 0
    @Published var pinboards: [SharedPinboardSummary] = []
    @Published var isLoading = true
    @Published var isSaving = false
    @Published var errorMessage: String?
}

final class ShareViewController: UIViewController {
    private let state = ShareExtensionState()
    private var payloads: [ClipItemPayload] = []
    private var saveService: ShareExtensionSaveService?
    private var queryService: SharedClipQueryService?
    private let payloadLoader = ShareExtensionPayloadLoader()

    override func viewDidLoad() {
        super.viewDidLoad()
        configureHostView()

        Task { @MainActor in
            await prepareData()
        }
    }

    @MainActor
    private func configureHostView() {
        let hostingController = UIHostingController(
            rootView: ObservingShareRootView(
                state: state,
                onSave: { [weak self] pinboardID in
                    Task { @MainActor in
                        await self?.save(to: pinboardID)
                    }
                },
                onCancel: { [weak self] in
                    self?.cancel()
                }
            )
        )
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostingController.didMove(toParent: self)
    }

    @MainActor
    private func prepareData() async {
        state.isLoading = true
        state.errorMessage = nil

        do {
            let storage = MartenIOSStorageConfiguration()
            let persistence = try storage.makePersistenceController()
            let assetStore = try storage.makeAssetStore()
            let saveService = ShareExtensionSaveService(
                persistenceController: persistence,
                assetStore: assetStore
            )
            let queryService = SharedClipQueryService(persistenceController: persistence)
            self.saveService = saveService
            self.queryService = queryService

            let providers = extractItemProviders()
            let payloads = await payloadLoader.loadPayloads(from: providers)
            self.payloads = payloads
            state.payloadCount = payloads.count
            state.pinboards = (try? await queryService.pinboards()) ?? []
        } catch {
            state.errorMessage = error.localizedDescription
        }

        state.isLoading = false
    }

    @MainActor
    private func save(to pinboardID: UUID?) async {
        guard let saveService else {
            state.errorMessage = "Save service unavailable."
            return
        }
        guard !payloads.isEmpty else {
            state.errorMessage = "No supported content found."
            return
        }

        state.isSaving = true
        defer { state.isSaving = false }

        do {
            _ = try await saveService.save(
                payloads: payloads,
                toPinboardID: pinboardID
            )
            let timestamp = Date().timeIntervalSince1970
            let groupDefaults = UserDefaults(suiteName: MartenIOSStorageConfiguration.defaultAppGroupIdentifier)
            groupDefaults?.set(timestamp, forKey: MartenIOSDefaults.shareExtensionLastSuccessAtKey)
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    private func extractItemProviders() -> [NSItemProvider] {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            return []
        }
        return items.flatMap { $0.attachments ?? [] }
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: "MartenShareExtension", code: 0))
    }
}

private struct ObservingShareRootView: View {
    @ObservedObject var state: ShareExtensionState
    let onSave: (UUID?) -> Void
    let onCancel: () -> Void

    var body: some View {
        ShareRootView(
            payloadCount: state.payloadCount,
            pinboards: state.pinboards,
            isLoading: state.isLoading,
            isSaving: state.isSaving,
            errorMessage: state.errorMessage,
            onSave: onSave,
            onCancel: onCancel
        )
    }
}
