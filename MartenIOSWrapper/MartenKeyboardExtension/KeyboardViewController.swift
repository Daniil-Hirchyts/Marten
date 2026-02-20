import MartenCore
import MartenIOSApp
import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private var hostingController: UIHostingController<KeyboardRootView>?
    private var heightConstraint: NSLayoutConstraint?
    private let payloadLoader = ShareExtensionPayloadLoader()
    private var saveService: ShareExtensionSaveService?
    private var pasteboardMonitorTimer: Timer?
    private var lastObservedChangeCount: Int = 0
    private var viewModel: KeyboardExtensionViewModel?

    override func viewDidLoad() {
        super.viewDidLoad()
        installRootView()
        setupKeyboardHeight()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startPasteboardMonitoring()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPasteboardMonitoring()
    }
    
    private func setupKeyboardHeight() {
        let height: CGFloat = 250
        heightConstraint?.isActive = false
        let constraint = view.heightAnchor.constraint(equalToConstant: height)
        constraint.priority = UILayoutPriority(999)
        constraint.isActive = true
        heightConstraint = constraint
    }

    private func installRootView() {
        let storage = MartenIOSStorageConfiguration()
        let persistence: PersistenceController
        let queryService: SharedClipQueryService
        let commandService: SharedClipCommandService

        if let configuredPersistence = try? storage.makePersistenceController() {
            persistence = configuredPersistence
            queryService = SharedClipQueryService(persistenceController: persistence)
            commandService = SharedClipCommandService(persistenceController: persistence)
        } else {
            persistence = PersistenceController()
            queryService = SharedClipQueryService(
                persistenceController: persistence
            )
            commandService = SharedClipCommandService(
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

        let viewModel = KeyboardExtensionViewModel(
            queryService: queryService,
            commandService: commandService
        )
        self.viewModel = viewModel
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
            onCopyClipboardToMarten: { [weak self] in
                guard let self else { return false }
                return await self.copyClipboardToMarten()
            },
            allowsNetworkFetch: hasFullAccess
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

    private func copyClipboardToMarten() async -> Bool {
        guard hasFullAccess else { return false }
        guard let saveService else { return false }

        let clipboardString = UIPasteboard.general.string ?? ""
        guard !clipboardString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        guard let payload = payloadLoader.payload(
            from: ShareExtensionPayloadCandidate(plainText: clipboardString)
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
            await viewModel?.refreshSilently()
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
    private func startPasteboardMonitoring() {
        stopPasteboardMonitoring()
        guard hasFullAccess else { return }
        
        lastObservedChangeCount = UIPasteboard.general.changeCount
        
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkForPasteboardChanges()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.pasteboardMonitorTimer = timer
    }

    private func stopPasteboardMonitoring() {
        pasteboardMonitorTimer?.invalidate()
        pasteboardMonitorTimer = nil
    }

    private func checkForPasteboardChanges() {
        guard hasFullAccess else { return }
        let currentCount = UIPasteboard.general.changeCount
        guard currentCount != lastObservedChangeCount else { return }
        
        lastObservedChangeCount = currentCount
        
        Task {
            _ = await copyClipboardToMarten()
        }
    }
}
