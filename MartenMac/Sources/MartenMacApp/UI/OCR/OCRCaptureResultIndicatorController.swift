import AppKit
import Foundation

@MainActor
protocol OCRResultIndicating: AnyObject {
    func showSuccess()
    func showFailure(message: String)
}

@MainActor
final class OCRCaptureResultIndicatorController: OCRResultIndicating {
    private static let showDuration: TimeInterval = 1.1

    private var panel: OCRIndicatorPanel?
    private var dismissWorkItem: DispatchWorkItem?
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var panelContentView: NSVisualEffectView?

    func showSuccess() {
        show(
            symbolName: "text.viewfinder",
            text: "Text Captured"
        )
    }

    func showFailure(message: String) {
        show(
            symbolName: "exclamationmark.triangle",
            text: message
        )
    }

    private func show(symbolName: String, text: String) {
        let panel = ensurePanel()

        let configuration = NSImage.SymbolConfiguration(pointSize: 40, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        iconView.contentTintColor = NSColor.white.withAlphaComponent(0.9)

        titleLabel.stringValue = text

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let size: CGFloat = 140
        let frame = CGRect(
            x: screen.frame.midX - size / 2,
            y: screen.frame.minY + 140,
            width: size,
            height: size
        )
        panel.setFrame(frame, display: true)

        dismissWorkItem?.cancel()
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        let dismiss = DispatchWorkItem { [weak panel] in
            guard let panel else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.orderOut(nil)
            }
        }
        dismissWorkItem = dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.showDuration, execute: dismiss)
    }

    private func ensurePanel() -> OCRIndicatorPanel {
        if let panel {
            return panel
        }

        let panel = OCRIndicatorPanel(
            contentRect: CGRect(x: 0, y: 0, width: 140, height: 140),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.alphaValue = 0
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true

        let panelContentView = NSVisualEffectView()
        panelContentView.material = .popover
        panelContentView.appearance = NSAppearance(named: .vibrantDark)
        panelContentView.state = .active
        panelContentView.blendingMode = .withinWindow
        panelContentView.wantsLayer = true
        panelContentView.layer?.cornerRadius = 20
        panelContentView.layer?.masksToBounds = true
        panelContentView.translatesAutoresizingMaskIntoConstraints = false

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 48),
            iconView.heightAnchor.constraint(equalToConstant: 48),
        ])

        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .white.withAlphaComponent(0.9)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        stackView.addArrangedSubview(iconView)
        stackView.addArrangedSubview(titleLabel)

        panelContentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: panelContentView.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: panelContentView.trailingAnchor, constant: -20),
            stackView.centerYAnchor.constraint(equalTo: panelContentView.centerYAnchor),
            panelContentView.widthAnchor.constraint(equalToConstant: 140),
            panelContentView.heightAnchor.constraint(equalToConstant: 140),
        ])

        panel.contentView = panelContentView
        self.panelContentView = panelContentView
        self.panel = panel
        return panel
    }
}

private final class OCRIndicatorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OCRNoopResultIndicator: OCRResultIndicating {
    func showSuccess() {}
    func showFailure(message: String) {}
}
