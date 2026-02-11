import AppKit
import Foundation
import QuickLookUI
import SwiftUI

struct FileQuickLookPreview: NSViewRepresentable {
    let fileURL: URL

    func makeNSView(context: Context) -> FileQuickLookContainerView {
        let container = FileQuickLookContainerView()
        container.update(fileURL: fileURL)
        return container
    }

    func updateNSView(_ nsView: FileQuickLookContainerView, context: Context) {
        nsView.update(fileURL: fileURL)
    }
}

final class FileQuickLookContainerView: NSView {
    private let previewView: QLPreviewView?
    private let fallbackLabel = NSTextField(labelWithString: "Preview unavailable")
    private var pendingFileURL: URL?
    private var appliedPath: String?

    override init(frame frameRect: NSRect) {
        previewView = QLPreviewView(frame: .zero, style: .normal)
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        previewView = QLPreviewView(frame: .zero, style: .normal)
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        if let previewView {
            previewView.translatesAutoresizingMaskIntoConstraints = false
            previewView.autostarts = true
            previewView.shouldCloseWithWindow = false
            addSubview(previewView)
            NSLayoutConstraint.activate([
                previewView.leadingAnchor.constraint(equalTo: leadingAnchor),
                previewView.trailingAnchor.constraint(equalTo: trailingAnchor),
                previewView.topAnchor.constraint(equalTo: topAnchor),
                previewView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        } else {
            fallbackLabel.alignment = .center
            fallbackLabel.font = .systemFont(ofSize: 13, weight: .medium)
            fallbackLabel.textColor = .secondaryLabelColor
            fallbackLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(fallbackLabel)
            NSLayoutConstraint.activate([
                fallbackLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
                fallbackLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            appliedPath = nil
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyPendingPreviewIfPossible()
    }

    func update(fileURL: URL) {
        pendingFileURL = fileURL
        applyPendingPreviewIfPossible()
    }

    private func applyPendingPreviewIfPossible() {
        guard window != nil, let previewView, let pendingFileURL else { return }
        guard appliedPath != pendingFileURL.path else { return }
        appliedPath = pendingFileURL.path
        previewView.previewItem = pendingFileURL as NSURL
        previewView.refreshPreviewItem()
    }
}
