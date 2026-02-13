import MartenCore
import MartenIOSApp
import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private var hostingController: UIHostingController<KeyboardRootView>?
    private var heightConstraint: NSLayoutConstraint?

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
        let queryService: SharedClipQueryService

        if
            let persistence = try? MartenIOSStorageConfiguration().makePersistenceController()
        {
            queryService = SharedClipQueryService(persistenceController: persistence)
        } else {
            queryService = SharedClipQueryService(
                persistenceController: PersistenceController()
            )
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
}
