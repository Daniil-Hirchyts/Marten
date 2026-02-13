import MartenCore
import MartenIOSApp
import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private var hostingController: UIHostingController<KeyboardRootView>?
    private var heightConstraint: NSLayoutConstraint?
    private let payloadLoader = ShareExtensionPayloadLoader()
    private var saveService: ShareExtensionSaveService?

    override func viewDidLoad() {
        super.viewDidLoad()
        installRootView()
        setupKeyboardHeight()
    }
    
    private func setupKeyboardHeight() {
        // Set a fixed height for the keyboard extension
        let height: CGFloat = 280
        let constraint = view.heightAnchor.constraint(equalToConstant: height)
        constraint.priority = .required
        constraint.isActive = true
        heightConstraint = constraint
    }

    private func installRootView() {
        let storage = MartenIOSStorageConfiguration()
        let persistence: PersistenceController
        let queryService: SharedClipQueryService

        if let configuredPersistence = try? storage.makePersistenceController() {
            persistence = configuredPersistence
            queryService = SharedClipQueryService(persistenceController: persistence)
        } else {
            persistence = PersistenceController()
            queryService = SharedClipQueryService(
                persistenceController: persistence
            )
        }

        if let assetStore = try? storage.makeAssetStore() {
            saveService = ShareExtensionSaveService(
                persistenceController: persistence,
                assetStore: assetStore
            )
        } else {
            saveService = ShareExtensionSaveService(persistenceController: persistence)
        }

        let viewModel = KeyboardExtensionViewModel(queryService: queryService)
        let rootView = KeyboardRootView(
            viewModel: viewModel,
            onInsertText: { [weak self] text in
                self?.textDocumentProxy.insertText(text)
            },
            onDeleteBackward: { [weak self] in
                self?.textDocumentProxy.deleteBackward()
            },
            onRecordHeartbeat: { [weak self] in
                self?.recordHeartbeat()
            },
            onCopySelectionToMarten: { [weak self] in
                guard let self else { return false }
                return await self.copySelectedTextToMarten()
            },
            allowsNetworkFetch: hasFullAccess,
            onOpenApp: { [weak self] url in
                self?.extensionContext?.open(url, completionHandler: nil)
            }
        )

        let hostingController = UIHostingController(rootView: rootView)
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostingController.didMove(toParent: self)
        self.hostingController = hostingController
    }

    private func recordHeartbeat() {
        guard hasFullAccess else { return }
        let timestamp = Date().timeIntervalSince1970
        let groupDefaults = UserDefaults(suiteName: MartenIOSStorageConfiguration.defaultAppGroupIdentifier)
        groupDefaults?.set(timestamp, forKey: MartenIOSDefaults.keyboardLastSeenAtKey)
    }

    private func copySelectedTextToMarten() async -> Bool {
        guard hasFullAccess else { return false }
        guard let saveService else { return false }

        let rawSelection = textDocumentProxy.selectedText ?? ""
        guard !rawSelection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        guard let payload = payloadLoader.payload(
            from: ShareExtensionPayloadCandidate(plainText: rawSelection)
        ) else {
            return false
        }

        do {
            let sourceAppInfo = MartenSourceIdentity.sourceAppInfo(
                iconData: MartenSourceIdentity.iconData(for: sourceAppIconCandidateBundles())
            )
            _ = try await saveService.save(
                payloads: [payload],
                toPinboardID: nil,
                sourceApp: sourceAppInfo
            )
            recordHeartbeat()
            let timestamp = Date().timeIntervalSince1970
            let groupDefaults = UserDefaults(suiteName: MartenIOSStorageConfiguration.defaultAppGroupIdentifier)
            groupDefaults?.set(timestamp, forKey: MartenIOSDefaults.shareExtensionLastSuccessAtKey)
            return true
        } catch {
            return false
        }
    }

    private func sourceAppIconCandidateBundles() -> [Bundle] {
        if let containingAppBundle = containingAppBundle() {
            return [containingAppBundle]
        }
        return [Bundle.main]
    }

    private func containingAppBundle() -> Bundle? {
        let extensionBundleURL = Bundle.main.bundleURL
        let plugInsURL = extensionBundleURL.deletingLastPathComponent()
        let appBundleURL = plugInsURL.deletingLastPathComponent()
        guard appBundleURL.pathExtension.lowercased() == "app" else {
            return nil
        }
        return Bundle(url: appBundleURL)
    }
}
