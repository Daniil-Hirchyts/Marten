import AppKit
@preconcurrency import ClipboardCore
import SwiftUI
import OSLog

@MainActor
final class ItemEditorWindowController {
    private let panel: NSPanel
    private var isVisible = false
    private var onSave: ((String) -> Void)?
    private var onClose: (() -> Void)?

    init() {
        let initialFrame = NSRect(x: 0, y: 0, width: 720, height: 520)
        panel = ItemEditorPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false  // Shadow is handled in SwiftUI
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isMovable = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.minSize = NSSize(width: 480, height: 360)
        panel.maxSize = NSSize(width: 1200, height: 900)
    }

    func show(item: ClipItem, onSave: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        guard !isVisible else { return }

        self.onSave = onSave
        self.onClose = onClose

        let contentView = ItemEditorContentView(
            item: item,
            onCancel: { [weak self] in
                self?.hide()
            },
            onSave: { [weak self] newText in
                onSave(newText)
                self?.hide()
            }
        )
        .ignoresSafeArea()

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        // Center the window on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = panel.frame
            let x = screenFrame.midX - windowFrame.width / 2
            let y = screenFrame.midY - windowFrame.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        isVisible = true
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.onClose?()
                self.onSave = nil
                self.onClose = nil
            }
        }
    }
}

private final class ItemEditorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func becomeKey() {
        super.becomeKey()
        makeFirstResponder(contentView)
    }

    override func keyDown(with event: NSEvent) {
        // Escape key
        if event.keyCode == 53 {
            close()
            return
        }

        super.keyDown(with: event)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        // Ensure content view fills the entire frame
        if let contentView = contentView {
            contentView.frame = NSRect(x: 0, y: 0, width: frameRect.width, height: frameRect.height)
        }
    }
}

private struct ItemEditorContentView: View {
    let item: ClipItem
    let onCancel: () -> Void
    let onSave: (String) -> Void

    private let store = ClipItemStore()

    @State private var draftText: String
    @State private var isBold = false
    @State private var isItalic = false
    @State private var isUnderline = false
    @State private var isStrikethrough = false
    @State private var fileName: String
    @State private var rotationAngle: Angle = .zero
    @State private var loadedImage: NSImage?
    @State private var originalImage: NSImage? // Keep original for applying full rotation
    @State private var loadedFileIcon: NSImage?
    @State private var initialRichTextContent: NSAttributedString?
    @State private var draftAttributedText: NSAttributedString?
    @FocusState private var isFocused: Bool

    init(item: ClipItem, onCancel: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        self.item = item
        self.onCancel = onCancel
        self.onSave = onSave

        let initialRichText =
            item.itemTypeValue == .richText ? item.styledTextContentWithoutTextColor : nil
        _initialRichTextContent = State(initialValue: initialRichText)
        _draftAttributedText = State(initialValue: initialRichText)
        _draftText = State(initialValue: initialRichText?.string ?? item.primaryText ?? "")

        // Extract filename from path for files or images
        if item.itemTypeValue == .file, let filePath = item.primaryText {
            let url = URL(fileURLWithPath: filePath)
            _fileName = State(initialValue: url.lastPathComponent)
        } else if item.itemTypeValue == .image {
            // Try to get filename from representations
            if let path = Self.getFilePathFromRepresentations(item) {
                let url = URL(fileURLWithPath: path)
                _fileName = State(initialValue: url.lastPathComponent)
            } else {
                _fileName = State(initialValue: "image.png")
            }
        } else {
            _fileName = State(initialValue: "Untitled")
        }
    }

    private static func getFilePathFromRepresentations(_ item: ClipItem) -> String? {
        guard let reps = item.representations else { return nil }
        guard let rep = reps.first(where: { $0.kindValue == .fileURL }) else { return nil }
        guard let data = rep.textData, let path = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Drag handle
                dragHandle
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                VStack(spacing: 16) {
                    toolbar
                    editorSurface
                    footer
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Resize indicator
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.30))
                        .padding(12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundView)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 15)
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            isFocused = true
            if item.itemTypeValue == .image {
                loadImageAsync()
            } else if item.itemTypeValue == .file {
                loadFileIconAsync()
            }
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        if #available(macOS 26.0, *) {
            Rectangle()
                .fill(Color.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: 20, style: .continuous))
        } else {
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
        }
    }

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.white.opacity(0.25))
            .frame(width: 36, height: 5)
    }

    private var toolbar: some View {
        VStack(spacing: 12) {
            // Top row: Cancel, Title, Save
            HStack(spacing: 12) {
                // Cancel button
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(10)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.12))
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                )
                .contentShape(Circle())
                .keyboardShortcut(.cancelAction)

                Spacer(minLength: 0)

                // Title
                Text(editorTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.90))

                Spacer(minLength: 0)

                // Save button
                Button {
                    handleSave()
                } label: {
                    Text("Save")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(
                                    canSave
                                        ? Color(nsColor: .systemBlue)
                                        : Color.white.opacity(0.20)
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .contentShape(Capsule())
                .keyboardShortcut(.return, modifiers: .command)
            }

            // Bottom row: Text modifiers (only for text editing)
            if supportsTextEditing && item.itemTypeValue != .code {
                HStack(spacing: 8) {
                    TextModifierButton(
                        icon: "bold",
                        isActive: isBold,
                        action: {
                            isBold.toggle()
                            applyFormatting(.bold)
                        }
                    )

                    TextModifierButton(
                        icon: "italic",
                        isActive: isItalic,
                        action: {
                            isItalic.toggle()
                            applyFormatting(.italic)
                        }
                    )

                    TextModifierButton(
                        icon: "underline",
                        isActive: isUnderline,
                        action: {
                            isUnderline.toggle()
                            applyFormatting(.underline)
                        }
                    )

                    TextModifierButton(
                        icon: "strikethrough",
                        isActive: isStrikethrough,
                        action: {
                            isStrikethrough.toggle()
                            applyFormatting(.strikethrough)
                        }
                    )

                    Spacer()

                    Button {
                        // Copy to clipboard
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(draftText, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.70))
                    .help("Copy to Clipboard")
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func handleSave() {
        switch item.itemTypeValue {
        case .image:
            // Save rotated image and filename
            let totalRotation = rotationAngle.degrees.truncatingRemainder(dividingBy: 360)
            if let original = originalImage, totalRotation != 0 {
                // Apply the FULL accumulated rotation to the original image
                let finalImage = applyRotationToImage(original, degrees: totalRotation)
                if let imageData = imageDataFrom(finalImage) {
                    do {
                        try store.updateImageData(objectID: item.objectID, imageData: imageData)
                    } catch {
                        NSSound.beep()
                    }
                }
            }
            // Filename changes for images are saved through customTitle
            if fileName != originalFileName {
                do {
                    try store.renameItem(objectID: item.objectID, title: fileName)
                } catch {
                    NSSound.beep()
                }
            }
            onSave(fileName)

        case .file:
            // For files, save the filename change
            if fileName != originalFileName {
                do {
                    try store.updateFileName(objectID: item.objectID, newFileName: fileName)
                } catch {
                    NSSound.beep()
                }
            }
            onSave(fileName)

        default:
            // For text-like items, persist edit directly from editor.
            do {
                if item.itemTypeValue == .richText {
                    let attributed =
                        draftAttributedText?.removingTextColorAttributes()
                        ?? NSAttributedString(
                            string: draftText,
                            attributes: [.font: NSFont.systemFont(ofSize: 16)]
                        )
                    guard let rtfData = attributed.clipboardData(for: .rtf) else {
                        NSSound.beep()
                        return
                    }
                    try store.updateRichTextItem(
                        objectID: item.objectID,
                        newText: attributed.string,
                        rtfData: rtfData
                    )
                } else {
                    try store.updateTextItem(objectID: item.objectID, newText: draftText)
                }
            } catch {
                NSSound.beep()
                return
            }
            onSave(draftText)
        }
    }

    private var originalFileName: String {
        if item.itemTypeValue == .file, let filePath = item.primaryText {
            return URL(fileURLWithPath: filePath).lastPathComponent
        } else if item.itemTypeValue == .image {
            if let path = Self.getFilePathFromRepresentations(item) {
                return URL(fileURLWithPath: path).lastPathComponent
            } else {
                return "image.png"
            }
        }
        return "Untitled"
    }

    private func imageDataFrom(_ image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmapImage.representation(using: .png, properties: [:])
    }

    private var canSave: Bool {
        switch item.itemTypeValue {
        case .file, .image:
            return !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return supportsTextEditing
        }
    }

    private var editorTitle: String {
        switch item.itemTypeValue {
        case .code:
            return "Edit Code"
        case .url:
            return "Edit URL"
        case .color:
            return "Edit Color"
        case .image:
            return "Edit Image"
        case .file:
            return "Edit File"
        default:
            return "Edit Text"
        }
    }

    private var editorSurface: some View {
        ZStack(alignment: .topLeading) {
            // Background
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )

            contentView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var contentView: some View {
        switch item.itemTypeValue {
        case .text, .richText, .url, .color:
            RichTextEditor(
                text: $draftText,
                attributedText: $draftAttributedText,
                initialAttributedText: item.itemTypeValue == .richText ? initialRichTextContent : nil,
                font: editorFont,
                onBold: { applyFormatting(.bold) },
                onItalic: { applyFormatting(.italic) },
                onUnderline: { applyFormatting(.underline) },
                onStrikethrough: { applyFormatting(.strikethrough) }
            )
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id("richTextEditor")

        case .code:
            TextEditor(text: $draftText)
                .font(editorFont)
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .file:
            fileEditorView

        case .image:
            imageEditorView

        default:
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(.yellow.opacity(0.8))

                Text("Editing isn't supported for this item type")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.70))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
    }

    private var fileEditorView: some View {
        VStack(spacing: 16) {
            // File preview card with floating toolbar
            ZStack(alignment: .topTrailing) {
                // File preview
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))

                    VStack(spacing: 20) {
                        // File icon
                        if let icon = loadedFileIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 96, height: 96)
                        } else {
                            Image(systemName: fileIconSystemName)
                                .font(.system(size: 64, weight: .light))
                                .foregroundStyle(.white.opacity(0.60))
                        }

                        // File name preview (non-editable display)
                        VStack(spacing: 6) {
                            Text(fileName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)

                            if let ext = fileExtension {
                                Text(ext.uppercased())
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.50))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(Color.white.opacity(0.10))
                                    )
                            }
                        }
                    }
                    .padding(32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )

                // Floating action buttons (always visible)
                HStack(spacing: 8) {
                    fileActionButton(icon: "folder", tooltip: "Show in Finder") {
                        revealInFinder()
                    }

                    fileActionButton(icon: "arrow.up.forward.app", tooltip: "Open") {
                        openFile()
                    }

                    fileActionButton(icon: "doc.on.doc", tooltip: "Copy Path") {
                        copyFilePath()
                    }
                }
                .padding(12)
            }

            // Compact metadata and rename section
            VStack(spacing: 12) {
                // Metadata row
                HStack(spacing: 16) {
                    if item.byteCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "doc")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.50))
                            Text(formatFileSize(item.byteCount))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.70))
                        }
                    }

                    if let ext = fileExtension {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.50))
                            Text(ext.uppercased())
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.70))
                        }
                    }

                    Spacer()
                }

                // File path
                if let path = filePath {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Location")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.50))
                            .textCase(.uppercase)

                        Text(path)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.60))
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                }

                // Inline rename field
                HStack(spacing: 8) {
                    Text("Rename:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.60))

                    TextField("", text: $fileName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func fileActionButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.60))
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        )
        .help(tooltip)
    }

    private var fileExtension: String? {
        fileName.split(separator: ".").last.map(String.init)
    }

    private var filePath: String? {
        item.primaryText
    }

    private var imageEditorView: some View {
        VStack(spacing: 16) {
            // Image preview with floating toolbar
            ZStack(alignment: .topTrailing) {
                if let image = loadedImage {
                    // Image with transparency grid
                    ZStack {
                        TransparencyGrid(squareSize: 10)
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .rotationEffect(rotationAngle)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    )

                    // Floating action buttons (always visible)
                    HStack(spacing: 8) {
                        imageActionButton(icon: "rotate.left", tooltip: "Rotate Left") {
                            rotateImage(direction: .left)
                        }

                        imageActionButton(icon: "rotate.right", tooltip: "Rotate Right") {
                            rotateImage(direction: .right)
                        }

                        imageActionButton(icon: "doc.on.doc", tooltip: "Copy") {
                            copyImageToClipboard()
                        }

                        imageActionButton(icon: "square.and.arrow.down", tooltip: "Save As...") {
                            saveImageToFile()
                        }
                    }
                    .padding(12)
                } else {
                    // Loading placeholder
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                        VStack(spacing: 12) {
                            Image(systemName: "photo")
                                .font(.system(size: 48, weight: .light))
                                .foregroundStyle(.white.opacity(0.50))
                            Text("Loading image...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.50))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            // Compact metadata and rename section
            VStack(spacing: 12) {
                if let image = loadedImage {
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Image(systemName: "aspectratio")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.50))
                            Text("\(Int(image.size.width))×\(Int(image.size.height))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.70))
                        }

                        if item.byteCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "doc")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.50))
                                Text(formatFileSize(item.byteCount))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.70))
                            }
                        }

                        Spacer()
                    }
                }

                // Inline rename field
                HStack(spacing: 8) {
                    Text("Rename:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.60))

                    TextField("", text: $fileName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func imageActionButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.60))
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        )
        .help(tooltip)
    }

    private func loadImageAsync() {
        // First try thumbnail path (fastest)
        if let thumbnailPath = item.thumbnailPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !thumbnailPath.isEmpty,
           let image = NSImage(contentsOfFile: thumbnailPath) {
            loadedImage = image
            originalImage = image // Store original for rotation
            return
        }

        // Then try to load from representations
        DispatchQueue.global(qos: .userInitiated).async {
            let image = self.loadImageFromRepresentations()
            DispatchQueue.main.async {
                self.loadedImage = image
                self.originalImage = image // Store original for rotation
            }
        }
    }

    private func loadFileIconAsync() {
        guard let path = filePathFromRepresentations() else {
            loadedFileIcon = nil
            return
        }
        loadedFileIcon = NSWorkspace.shared.icon(forFile: path)
    }

    private func loadImageFromRepresentations() -> NSImage? {
        guard let representations = item.representations else { return nil }

        // Try PNG, JPEG, TIFF representations
        for rep in representations {
            let kind = rep.kindValue
            if kind == .png || kind == .jpeg || kind == .tiff {
                if let data = rep.binaryData, let image = NSImage(data: data) {
                    return image
                }
            }
        }

        return nil
    }

    private func getImageData() -> Data? {
        // Try to get image data from representations
        guard let representations = item.representations else { return nil }
        for rep in representations {
            let kind = rep.kindValue
            if kind == .png || kind == .jpeg || kind == .tiff {
                if let data = rep.binaryData {
                    return data
                }
            }
        }
        return nil
    }

    private func filePathFromRepresentations() -> String? {
        guard let reps = item.representations else { return nil }
        guard let rep = reps.first(where: { $0.kindValue == .fileURL }) else { return nil }
        guard let data = rep.textData, let path = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.50))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.70))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var fileIconSystemName: String {
        let ext = fileName.split(separator: ".").last?.lowercased() ?? ""

        if ext == "pdf" {
            return "doc.richtext.fill"
        } else if ext == "zip" || ext == "tar" || ext == "gz" {
            return "doc.zipper"
        } else if ext == "mp4" || ext == "mov" || ext == "avi" {
            return "film.fill"
        } else if ext == "mp3" || ext == "wav" || ext == "m4a" {
            return "music.note"
        } else {
            return "doc.fill"
        }
    }

    private var fileIcon: String {
        let ext = fileName.split(separator: ".").last?.lowercased() ?? ""

        if ext == "pdf" {
            return "doc.richtext.fill"
        } else if ext == "zip" || ext == "tar" || ext == "gz" {
            return "doc.zipper"
        } else if ext == "mp4" || ext == "mov" || ext == "avi" {
            return "film.fill"
        } else if ext == "mp3" || ext == "wav" || ext == "m4a" {
            return "music.note"
        } else {
            return "doc.fill"
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func revealInFinder() {
        guard let filePath = item.primaryText else { return }
        NSWorkspace.shared.selectFile(filePath, inFileViewerRootedAtPath: "")
    }

    private func openFile() {
        guard let filePath = item.primaryText else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: filePath))
    }

    private func copyFilePath() {
        if let path = filePathFromRepresentations() {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(path, forType: .string)
        }
    }

    private func rotateImage(direction: RotationDirection) {
        let rotationDegrees: Double = direction == .left ? -90 : 90
        withAnimation(.easeInOut(duration: 0.3)) {
            rotationAngle += Angle(degrees: rotationDegrees)
        }
    }

    private func copyImageToClipboard() {
        guard let image = originalImage else {
            NSSound.beep()
            return
        }

        // Apply full accumulated rotation
        let totalRotation = rotationAngle.degrees.truncatingRemainder(dividingBy: 360)
        let finalImage = applyRotationToImage(image, degrees: totalRotation)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([finalImage])
    }

    private func saveImageToFile() {
        guard let image = originalImage else {
            NSSound.beep()
            return
        }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png, .jpeg, .tiff]
        savePanel.nameFieldStringValue = fileName
        savePanel.canCreateDirectories = true
        savePanel.title = "Save Image"

        // Make sure panel appears in front by using runModal
        let response = savePanel.runModal()

        if response == .OK, let url = savePanel.url {
            // Apply full accumulated rotation
            let totalRotation = rotationAngle.degrees.truncatingRemainder(dividingBy: 360)
            let finalImage = applyRotationToImage(image, degrees: totalRotation)
            saveImage(finalImage, to: url)
        }
    }

    private func applyRotationToImage(_ image: NSImage, degrees: Double) -> NSImage {
        if degrees == 0 {
            return image
        }

        let radians = CGFloat(degrees * .pi / 180.0)

        // Calculate new size after rotation
        let originalSize = image.size
        let rotatedWidth = abs(originalSize.width * cos(radians)) + abs(originalSize.height * sin(radians))
        let rotatedHeight = abs(originalSize.width * sin(radians)) + abs(originalSize.height * cos(radians))
        let newSize = NSSize(width: rotatedWidth, height: rotatedHeight)

        let rotatedImage = NSImage(size: newSize)
        rotatedImage.lockFocus()

        let transform = NSAffineTransform()
        transform.translateX(by: newSize.width / 2, yBy: newSize.height / 2)
        transform.rotate(byRadians: -radians)  // Negate to make positive = clockwise
        transform.translateX(by: -originalSize.width / 2, yBy: -originalSize.height / 2)
        transform.concat()

        image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)

        rotatedImage.unlockFocus()
        return rotatedImage
    }

    private func saveImage(_ image: NSImage, to url: URL) {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else {
            NSSound.beep()
            return
        }

        let fileType: NSBitmapImageRep.FileType
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            fileType = .jpeg
        case "tif", "tiff":
            fileType = .tiff
        default:
            fileType = .png
        }

        guard let imageData = bitmapImage.representation(using: fileType, properties: [:]) else {
            NSSound.beep()
            return
        }

        do {
            try imageData.write(to: url)
        } catch {
            NSSound.beep()
            print("Failed to save image: \(error)")
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            // Left side: Stats/Info
            Group {
                switch item.itemTypeValue {
                case .text, .richText, .code, .url, .color:
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11, weight: .medium))
                        Text(TextStats(text: draftText).label)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.60))

                case .file:
                    HStack(spacing: 6) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 11, weight: .medium))
                        Text("File Editor")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.60))

                case .image:
                    HStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 11, weight: .medium))
                        Text("Image Viewer")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.60))

                default:
                    EmptyView()
                }
            }

            Spacer(minLength: 0)

            // Keyboard hints
            HStack(spacing: 12) {
                KeyboardHint(key: "⎋", label: "Cancel")
                if supportsEditing {
                    KeyboardHint(key: "⌘↩", label: "Save")
                }
            }
        }
    }

    private var supportsTextEditing: Bool {
        switch item.itemTypeValue {
        case .text, .richText, .code, .url, .color:
            true
        default:
            false
        }
    }

    private var supportsEditing: Bool {
        switch item.itemTypeValue {
        case .text, .richText, .code, .url, .color, .file, .image:
            true
        default:
            false
        }
    }

    private var editorFont: Font {
        item.itemTypeValue == .code
            ? .system(size: 16, weight: .regular, design: .monospaced)
            : .system(size: 16)
    }

    private func applyFormatting(_ type: TextFormattingType) {
        // This will be called by the RichTextEditor through the toolbar buttons
        NotificationCenter.default.post(
            name: .applyTextFormatting,
            object: nil,
            userInfo: ["type": type]
        )
    }
}

enum TextFormattingType {
    case bold, italic, underline, strikethrough
}

enum RotationDirection {
    case left, right
}

extension Notification.Name {
    static let applyTextFormatting = Notification.Name("applyTextFormatting")
}

struct RichTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var attributedText: NSAttributedString?
    let initialAttributedText: NSAttributedString?
    let font: Font
    let onBold: () -> Void
    let onItalic: () -> Void
    let onUnderline: () -> Void
    let onStrikethrough: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.isRichText = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false

        // Set text color and background
        textView.textColor = .white
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.insertionPointColor = .white

        // Set font
        let nsFont = NSFont.systemFont(ofSize: 16, weight: .regular)
        textView.font = nsFont

        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        // Set initial text
        if let initialAttributedText, initialAttributedText.length > 0 {
            textView.textStorage?.setAttributedString(initialAttributedText)
            context.coordinator.sanitizeUnsupportedAttributes(in: textView)
            text = initialAttributedText.string
            context.coordinator.attributedText = textView.attributedString()
        } else {
            textView.string = text
            context.coordinator.sanitizeUnsupportedAttributes(in: textView)
            context.coordinator.attributedText = textView.attributedString()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(selectedRange)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            attributedText: $attributedText,
            onBold: onBold,
            onItalic: onItalic,
            onUnderline: onUnderline,
            onStrikethrough: onStrikethrough
        )
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var attributedText: NSAttributedString?
        let onBold: () -> Void
        let onItalic: () -> Void
        let onUnderline: () -> Void
        let onStrikethrough: () -> Void
        weak var textView: NSTextView?
        private var observer: NSObjectProtocol?
        private var isSanitizingTextChange = false

        init(
            text: Binding<String>,
            attributedText: Binding<NSAttributedString?>,
            onBold: @escaping () -> Void,
            onItalic: @escaping () -> Void,
            onUnderline: @escaping () -> Void,
            onStrikethrough: @escaping () -> Void
        ) {
            _text = text
            _attributedText = attributedText
            self.onBold = onBold
            self.onItalic = onItalic
            self.onUnderline = onUnderline
            self.onStrikethrough = onStrikethrough
            super.init()

            // Listen for formatting commands
            observer = NotificationCenter.default.addObserver(
                forName: .applyTextFormatting,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let type = notification.userInfo?["type"] as? TextFormattingType else { return }
                self?.applyFormatting(type)
            }
        }

        deinit {
            if let observer = observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            sanitizeUnsupportedAttributes(in: textView)
            text = textView.string
            attributedText = textView.attributedString()
        }

        func sanitizeUnsupportedAttributes(in textView: NSTextView) {
            guard !isSanitizingTextChange, let textStorage = textView.textStorage else { return }
            guard textStorage.length > 0 else { return }

            isSanitizingTextChange = true
            defer { isSanitizingTextChange = false }

            let selectedRange = textView.selectedRange()
            let fullRange = NSRange(location: 0, length: textStorage.length)
            let sanitized = textStorage.removingTextColorAttributes()
            textStorage.setAttributedString(sanitized)

            // Enforce a single editor text color so pasted rich text cannot tint content.
            let baseColor = textView.textColor ?? NSColor.white
            textStorage.addAttribute(.foregroundColor, value: baseColor, range: fullRange)
            textView.typingAttributes[.foregroundColor] = baseColor
            textView.linkTextAttributes = [:]
            textView.setSelectedRange(selectedRange)
            attributedText = textView.attributedString()
        }

        func applyFormatting(_ type: TextFormattingType) {
            guard let textView = textView else { return }
            let selectedRange = textView.selectedRange()

            guard selectedRange.length > 0 else {
                // No selection, just toggle the trait for future typing
                toggleTrait(type)
                return
            }

            // Get the current attributes for the selection
            guard let textStorage = textView.textStorage else { return }
            let selectedText = (textStorage.string as NSString).substring(with: selectedRange)

            // Get current font
            var currentFont = textView.font ?? NSFont.systemFont(ofSize: 16)

            // Create attributed string
            let attributedString = NSMutableAttributedString(string: selectedText)

            // Apply formatting based on type
            switch type {
            case .bold:
                if currentFont.fontDescriptor.symbolicTraits.contains(.bold) {
                    // Remove bold
                    currentFont = NSFont.systemFont(ofSize: currentFont.pointSize, weight: .regular)
                } else {
                    // Add bold
                    currentFont = NSFont.systemFont(ofSize: currentFont.pointSize, weight: .bold)
                }
                attributedString.addAttribute(.font, value: currentFont, range: NSRange(location: 0, length: selectedText.count))

            case .italic:
                if currentFont.fontDescriptor.symbolicTraits.contains(.italic) {
                    // Remove italic
                    currentFont = NSFont.systemFont(ofSize: currentFont.pointSize)
                } else {
                    // Add italic
                    currentFont = NSFont(descriptor: currentFont.fontDescriptor.withSymbolicTraits(.italic), size: currentFont.pointSize) ?? currentFont
                }
                attributedString.addAttribute(.font, value: currentFont, range: NSRange(location: 0, length: selectedText.count))

            case .underline:
                // Toggle underline
                let hasUnderline = textStorage.attribute(.underlineStyle, at: selectedRange.location, effectiveRange: nil) != nil
                if hasUnderline {
                    attributedString.removeAttribute(.underlineStyle, range: NSRange(location: 0, length: selectedText.count))
                } else {
                    attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: selectedText.count))
                }
                attributedString.addAttribute(.font, value: currentFont, range: NSRange(location: 0, length: selectedText.count))

            case .strikethrough:
                // Toggle strikethrough
                let hasStrikethrough = textStorage.attribute(.strikethroughStyle, at: selectedRange.location, effectiveRange: nil) != nil
                if hasStrikethrough {
                    attributedString.removeAttribute(.strikethroughStyle, range: NSRange(location: 0, length: selectedText.count))
                } else {
                    attributedString.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: selectedText.count))
                }
                attributedString.addAttribute(.font, value: currentFont, range: NSRange(location: 0, length: selectedText.count))
            }

            // Replace the selected text with the formatted text
            textStorage.replaceCharacters(in: selectedRange, with: attributedString)
            sanitizeUnsupportedAttributes(in: textView)

            // Restore selection
            textView.setSelectedRange(selectedRange)
            text = textView.string
            attributedText = textView.attributedString()
        }

        func toggleTrait(_ type: TextFormattingType) {
            guard let textView = textView else { return }
            var currentFont = textView.font ?? NSFont.systemFont(ofSize: 16)

            switch type {
            case .bold:
                if currentFont.fontDescriptor.symbolicTraits.contains(.bold) {
                    currentFont = NSFont.systemFont(ofSize: currentFont.pointSize, weight: .regular)
                } else {
                    currentFont = NSFont.systemFont(ofSize: currentFont.pointSize, weight: .bold)
                }
                textView.font = currentFont

            case .italic:
                if currentFont.fontDescriptor.symbolicTraits.contains(.italic) {
                    currentFont = NSFont.systemFont(ofSize: currentFont.pointSize)
                } else {
                    currentFont = NSFont(descriptor: currentFont.fontDescriptor.withSymbolicTraits(.italic), size: currentFont.pointSize) ?? currentFont
                }
                textView.font = currentFont

            case .underline, .strikethrough:
                // These are applied to text as attributes, not font traits
                break
            }
        }
    }
}

private struct KeyboardHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.70))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                )

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.50))
        }
    }
}

private struct TextModifierButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? .white : .white.opacity(0.50))
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive ? Color.white.opacity(0.20) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            isActive ? Color.white.opacity(0.30) : Color.white.opacity(0.12),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

private struct TextStats: Equatable {
    let characters: Int
    let words: Int
    let lines: Int

    init(text: String) {
        characters = text.count
        words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        lines = max(1, text.split(separator: "\n", omittingEmptySubsequences: false).count)
    }

    var label: String {
        "\(characters) characters  •  \(words) words  •  \(lines) line\(lines == 1 ? "" : "s")"
    }
}
