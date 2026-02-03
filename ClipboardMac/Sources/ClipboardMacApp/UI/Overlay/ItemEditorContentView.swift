import AppKit
import ClipboardCore
import ClipboardMacServices
import OSLog
import SwiftUI

enum ItemEditorMode {
    case edit
    case createNew
}

struct ItemEditorContentView: View {
    let item: ClipItem?
    let onCancel: () -> Void
    let onSave: (String) -> Void
    let mode: ItemEditorMode

    private let clipItemEditor: any ClipItemEditing
    private let appleIntelligence: any AppleIntelligenceTextTransforming

    @State private var draftText: String
    @State private var isBold = false
    @State private var isItalic = false
    @State private var isUnderline = false
    @State private var isStrikethrough = false
    @State private var fileName: String
    @State private var rotationAngle: Angle = .zero
    @State private var loadedImage: NSImage?
    @State private var originalImage: NSImage?
    @State private var loadedFileIcon: NSImage?
    @State private var initialRichTextContent: NSAttributedString?
    @State private var draftAttributedText: NSAttributedString?
    @State private var richTextSelection: NSRange?
    @State private var codeSelection: TextSelection?
    @State private var appleIntelligenceAvailability: AppleIntelligenceAvailability = .unavailable(
        .modelNotReady)
    @State private var appleIntelligenceTask: Task<Void, Never>?
    @State private var appleIntelligenceError: String?
    @State private var appleIntelligencePreview: ItemEditorAppleIntelligencePreview?
    @FocusState private var isFocused: Bool

    private var unwrappedItem: ClipItem {
        guard let item = item else {
            fatalError("Item must not be nil when accessing existingItemBody path")
        }
        return item
    }

    init(
        item: ClipItem?,
        clipItemEditor: any ClipItemEditing,
        appleIntelligence: any AppleIntelligenceTextTransforming,
        mode: ItemEditorMode,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String) -> Void
    ) {
        self.item = item
        self.clipItemEditor = clipItemEditor
        self.appleIntelligence = appleIntelligence
        self.mode = mode
        self.onCancel = onCancel
        self.onSave = onSave

        if mode == .createNew {
            _initialRichTextContent = State(initialValue: nil)
            _draftAttributedText = State(initialValue: nil)
            _draftText = State(initialValue: "")
            _fileName = State(initialValue: "New Text Item")
        } else if let item = item {
            let initialRichText =
                item.itemTypeValue == .richText ? item.styledTextContentWithoutTextColor : nil
            _initialRichTextContent = State(initialValue: initialRichText)
            _draftAttributedText = State(initialValue: initialRichText)
            _draftText = State(initialValue: initialRichText?.string ?? item.primaryText ?? "")

            if item.itemTypeValue == .file, let filePath = item.primaryText {
                let url = URL(fileURLWithPath: filePath)
                _fileName = State(initialValue: url.lastPathComponent)
            } else if item.itemTypeValue == .image {
                if let path = Self.getFilePathFromRepresentations(item) {
                    let url = URL(fileURLWithPath: path)
                    _fileName = State(initialValue: url.lastPathComponent)
                } else {
                    _fileName = State(initialValue: "image.png")
                }
            } else {
                _fileName = State(initialValue: "Untitled")
            }
        } else {
            _initialRichTextContent = State(initialValue: nil)
            _draftAttributedText = State(initialValue: nil)
            _draftText = State(initialValue: "")
            _fileName = State(initialValue: "Untitled")
        }
    }

    private static func getFilePathFromRepresentations(_ item: ClipItem) -> String? {
        guard let reps = item.representations else { return nil }
        guard let rep = reps.first(where: { $0.kindValue == .fileURL }) else { return nil }
        guard let data = rep.textData, let path = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        if mode == .createNew {
            newTextItemBody
        } else {
            existingItemBody
        }
    }

    private var newTextItemBody: some View {
        ZStack {
            VStack(spacing: 0) {
                dragHandle
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                VStack(spacing: 16) {
                    newTextToolbar
                    newTextEditorSurface
                    footer
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
            // Check Apple Intelligence availability for new text items
            Task {
                await refreshAppleIntelligenceAvailability()
            }
        }
        .onDisappear {
            appleIntelligenceTask?.cancel()
            appleIntelligenceTask = nil
        }
        .sheet(item: $appleIntelligencePreview) { preview in
            appleIntelligencePreviewSheet(for: preview)
        }
    }

    private var existingItemBody: some View {
        ZStack {
            VStack(spacing: 0) {
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
            if let item = item {
                if unwrappedItem.itemTypeValue == .image {
                    loadImageAsync()
                } else if unwrappedItem.itemTypeValue == .file {
                    loadFileIconAsync()
                }
                if supportsCustomAppleIntelligenceActions {
                    Task {
                        await refreshAppleIntelligenceAvailability()
                    }
                }
            }
        }
        .onDisappear {
            appleIntelligenceTask?.cancel()
            appleIntelligenceTask = nil
        }
        .sheet(item: $appleIntelligencePreview) { preview in
            appleIntelligencePreviewSheet(for: preview)
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
            HStack(spacing: 12) {
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

                Text(editorTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.90))

                Spacer(minLength: 0)

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

            if supportsTextEditing {
                HStack(spacing: 8) {
                    if item?.itemTypeValue != .code {
                        ItemEditorTextModifierButton(
                            icon: "bold",
                            isActive: isBold,
                            action: {
                                isBold.toggle()
                                applyFormatting(.bold)
                            }
                        )

                        ItemEditorTextModifierButton(
                            icon: "italic",
                            isActive: isItalic,
                            action: {
                                isItalic.toggle()
                                applyFormatting(.italic)
                            }
                        )

                        ItemEditorTextModifierButton(
                            icon: "underline",
                            isActive: isUnderline,
                            action: {
                                isUnderline.toggle()
                                applyFormatting(.underline)
                            }
                        )

                        ItemEditorTextModifierButton(
                            icon: "strikethrough",
                            isActive: isStrikethrough,
                            action: {
                                isStrikethrough.toggle()
                                applyFormatting(.strikethrough)
                            }
                        )
                    }

                    if shouldShowAppleIntelligenceControl {
                        appleIntelligenceMenu
                    }

                    Spacer()

                    if item?.itemTypeValue != .code {
                        Button {
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
                }
                .padding(.horizontal, 4)

                if let appleIntelligenceError {
                    Text(appleIntelligenceError)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    private var appleIntelligenceMenu: some View {
        Menu {
            if supportsCustomAppleIntelligenceActions {
                ForEach(AppleIntelligenceTextAction.allCases, id: \.rawValue) { action in
                    Button(action.title) {
                        runAppleIntelligenceAction(action)
                    }
                    .disabled(!canRunAppleIntelligenceAction(action))
                }

                Divider()
            }

            Button("Open Writing Tools") {
                openSystemWritingTools(selectingFullTextIfNeeded: true)
            }
        } label: {
            ZStack {
                if isGeneratingAppleIntelligence {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white.opacity(0.9))
                } else {
                    Image(systemName: "apple.intelligence")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.50))
                }
            }
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isGeneratingAppleIntelligence ? Color.white.opacity(0.20) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isGeneratingAppleIntelligence
                            ? Color.white.opacity(0.30)
                            : Color.white.opacity(0.12),
                        lineWidth: 1
                    )
            )
        } primaryAction: {
            openSystemWritingTools(selectingFullTextIfNeeded: true)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help("Apple Intelligence")
        .accessibilityIdentifier("itemEditor.appleIntelligence.menu")
    }

    private func handleSave() {
        guard let item = item else {
            // For new text items - handle rich text if formatted
            if let attributed = draftAttributedText, attributed.length > 0 {
                // Check if there's actual formatting (check for bold, italic, underline, strikethrough)
                var hasFormatting = false
                attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attrs, _, stop in
                    if attrs[.font] != nil {
                        if let font = attrs[.font] as? NSFont {
                            if font.fontDescriptor.symbolicTraits.contains(.bold) || 
                               font.fontDescriptor.symbolicTraits.contains(.italic) {
                                hasFormatting = true
                                stop.pointee = true
                            }
                        }
                    }
                    if attrs[.underlineStyle] != nil || attrs[.strikethroughStyle] != nil {
                        hasFormatting = true
                        stop.pointee = true
                    }
                }
                
                if hasFormatting {
                    // Write rich text to pasteboard
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    
                    // Write both RTF and plain text
                    if let rtfData = attributed.clipboardData(for: .rtf) {
                        pasteboard.setData(rtfData, forType: .rtf)
                    }
                    pasteboard.setString(draftText, forType: .string)
                    
                    onSave(draftText)
                    return
                }
            }
            
            // Plain text fallback
            onSave(draftText)
            return
        }
        
        switch unwrappedItem.itemTypeValue {
        case .image:
            let totalRotation = rotationAngle.degrees.truncatingRemainder(dividingBy: 360)
            if let original = originalImage, totalRotation != 0 {
                let finalImage = applyRotationToImage(original, degrees: totalRotation)
                if let imageData = imageDataFrom(finalImage) {
                    do {
                        try clipItemEditor.updateImageData(
                            objectID: unwrappedItem.objectID, imageData: imageData)
                    } catch {
                        NSSound.beep()
                    }
                }
            }
            if fileName != originalFileName {
                do {
                    try clipItemEditor.renameItem(objectID: unwrappedItem.objectID, title: fileName)
                } catch {
                    NSSound.beep()
                }
            }
            onSave(fileName)

        case .file:
            if fileName != originalFileName {
                do {
                    try clipItemEditor.updateFileName(
                        objectID: unwrappedItem.objectID, newFileName: fileName)
                } catch {
                    NSSound.beep()
                }
            }
            onSave(fileName)

        default:
            do {
                if unwrappedItem.itemTypeValue == .richText {
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
                    _ = try clipItemEditor.updateRichTextItem(
                        objectID: unwrappedItem.objectID,
                        newText: attributed.string,
                        rtfData: rtfData
                    )
                } else {
                    _ = try clipItemEditor.updateTextItem(
                        objectID: unwrappedItem.objectID, newText: draftText)
                }
            } catch {
                NSSound.beep()
                return
            }
            onSave(draftText)
        }
    }

    private var originalFileName: String {
        guard let item = item else { return "Untitled" }
        if unwrappedItem.itemTypeValue == .file, let filePath = unwrappedItem.primaryText {
            return URL(fileURLWithPath: filePath).lastPathComponent
        } else if unwrappedItem.itemTypeValue == .image {
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
            let bitmapImage = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }
        return bitmapImage.representation(using: .png, properties: [:])
    }

    private var canSave: Bool {
        guard let item = item else {
            return !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        switch unwrappedItem.itemTypeValue {
        case .file, .image:
            return !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return supportsTextEditing
        }
    }

    private var editorTitle: String {
        guard let item = item else { return "New Text Item" }
        switch unwrappedItem.itemTypeValue {
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
        switch unwrappedItem.itemTypeValue {
        case .text, .richText, .url, .color:
            RichTextEditor(
                text: $draftText,
                attributedText: $draftAttributedText,
                selection: $richTextSelection,
                initialAttributedText: unwrappedItem.itemTypeValue == .richText
                    ? initialRichTextContent : nil,
                font: editorFont,
                writingToolsBehavior: richTextEditorWritingToolsBehavior,
                allowedWritingToolsResultOptions: richTextEditorWritingToolsResultOptions,
                onBold: { applyFormatting(.bold) },
                onItalic: { applyFormatting(.italic) },
                onUnderline: { applyFormatting(.underline) },
                onStrikethrough: { applyFormatting(.strikethrough) }
            )
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id("richTextEditor")

        case .code:
            TextEditor(text: $draftText, selection: $codeSelection)
                .font(editorFont)
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .writingToolsBehavior(.complete)
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
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))

                    VStack(spacing: 20) {
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

            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    if unwrappedItem.byteCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "doc")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.50))
                            Text(formatFileSize(unwrappedItem.byteCount))
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

    private func fileActionButton(icon: String, tooltip: String, action: @escaping () -> Void)
        -> some View
    {
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
        unwrappedItem.primaryText
    }

    private var imageEditorView: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .topTrailing) {
                if let image = loadedImage {
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

                        if unwrappedItem.byteCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "doc")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.50))
                                Text(formatFileSize(unwrappedItem.byteCount))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.70))
                            }
                        }

                        Spacer()
                    }
                }

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

    private func imageActionButton(icon: String, tooltip: String, action: @escaping () -> Void)
        -> some View
    {
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
        if let thumbnailPath = unwrappedItem.thumbnailPath?.trimmingCharacters(in: .whitespacesAndNewlines),
            !thumbnailPath.isEmpty,
            let image = NSImage(contentsOfFile: thumbnailPath)
        {
            loadedImage = image
            originalImage = image
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let image = self.loadImageFromRepresentations()
            DispatchQueue.main.async {
                self.loadedImage = image
                self.originalImage = image
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
        guard let representations = unwrappedItem.representations else { return nil }

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
        guard let representations = unwrappedItem.representations else { return nil }
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
        guard let reps = unwrappedItem.representations else { return nil }
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

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func revealInFinder() {
        guard let filePath = unwrappedItem.primaryText else { return }
        NSWorkspace.shared.selectFile(filePath, inFileViewerRootedAtPath: "")
    }

    private func openFile() {
        guard let filePath = unwrappedItem.primaryText else { return }
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

        let response = savePanel.runModal()

        if response == .OK, let url = savePanel.url {
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

        let originalSize = image.size
        let rotatedWidth =
            abs(originalSize.width * cos(radians)) + abs(originalSize.height * sin(radians))
        let rotatedHeight =
            abs(originalSize.width * sin(radians)) + abs(originalSize.height * cos(radians))
        let newSize = NSSize(width: rotatedWidth, height: rotatedHeight)

        let rotatedImage = NSImage(size: newSize)
        rotatedImage.lockFocus()

        let transform = NSAffineTransform()
        transform.translateX(by: newSize.width / 2, yBy: newSize.height / 2)
        transform.rotate(byRadians: -radians)
        transform.translateX(by: -originalSize.width / 2, yBy: -originalSize.height / 2)
        transform.concat()

        image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)

        rotatedImage.unlockFocus()
        return rotatedImage
    }

    private func saveImage(_ image: NSImage, to url: URL) {
        guard let tiffData = image.tiffRepresentation,
            let bitmapImage = NSBitmapImageRep(data: tiffData)
        else {
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
            Logger.ui.error(
                "Failed to save image: \(error.localizedDescription, privacy: .private)")
        }
    }

    private var supportsCustomAppleIntelligenceActions: Bool {
        // For new text items, support AI
        guard let item = item else { return true }
        
        switch item.itemTypeValue {
        case .text, .code, .url:
            return true
        default:
            return false
        }
    }

    private var shouldShowAppleIntelligenceControl: Bool {
        // For new text items, show if available
        guard let item = item else {
            return appleIntelligenceAvailability == .available
        }
        
        if supportsCustomAppleIntelligenceActions {
            return appleIntelligenceAvailability == .available
        }
        return item.itemTypeValue == .richText
    }

    private var isGeneratingAppleIntelligence: Bool {
        appleIntelligenceTask != nil
    }

    private var richTextEditorWritingToolsBehavior: NSWritingToolsBehavior {
        guard let item = item else { return .complete }
        switch item.itemTypeValue {
        case .text, .richText, .url:
            return .complete
        default:
            return .none
        }
    }

    private var richTextEditorWritingToolsResultOptions: NSWritingToolsResultOptions {
        guard let item = item else { return [.plainText, .richText, .table, .list] }
        if item.itemTypeValue == .richText {
            return [.richText, .list, .table, .presentationIntent]
        }
        return .plainText
    }

    private var codeSelectionRange: NSRange? {
        Self.nsRange(from: codeSelection, in: draftText)
    }

    private var currentAIResolvedTarget: ItemEditorAIResolvedTarget {
        let itemType: ItemType = item?.itemTypeValue ?? .text
        return ItemEditorAITextEditing.resolveTarget(
            itemType: itemType,
            draftText: draftText,
            richTextSelection: richTextSelection,
            codeSelection: codeSelectionRange
        )
    }

    private func canRunAppleIntelligenceAction(_ action: AppleIntelligenceTextAction) -> Bool {
        guard supportsCustomAppleIntelligenceActions else { return false }
        guard appleIntelligenceAvailability == .available else { return false }
        guard !isGeneratingAppleIntelligence else { return false }
        return !currentAIResolvedTarget.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private func refreshAppleIntelligenceAvailability() async {
        appleIntelligenceAvailability = await appleIntelligence.availability(for: .current)
    }

    private func runAppleIntelligenceAction(_ action: AppleIntelligenceTextAction) {
        guard supportsCustomAppleIntelligenceActions else { return }

        let target = currentAIResolvedTarget
        guard !target.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appleIntelligenceError = "No text available for Apple Intelligence."
            return
        }

        appleIntelligenceTask?.cancel()
        appleIntelligenceError = nil

        appleIntelligenceTask = Task {
            do {
                let transformed = try await appleIntelligence.transform(
                    target.sourceText,
                    action: action,
                    locale: .current
                )
                guard !Task.isCancelled else { return }
                appleIntelligencePreview = ItemEditorAppleIntelligencePreview(
                    action: action,
                    target: target,
                    transformedText: transformed
                )
                appleIntelligenceTask = nil
            } catch is CancellationError {
                if appleIntelligenceTask?.isCancelled == true {
                    appleIntelligenceTask = nil
                }
            } catch let error as AppleIntelligenceTextTransformationError {
                appleIntelligenceTask = nil
                appleIntelligenceError = appleIntelligenceErrorMessage(for: error)
            } catch {
                appleIntelligenceTask = nil
                appleIntelligenceError =
                    "Apple Intelligence couldn’t transform the text right now. Try again."
            }
        }
    }

    private func openSystemWritingTools(selectingFullTextIfNeeded: Bool = false) {
        if selectingFullTextIfNeeded {
            selectAllTextForWritingToolsIfNeeded()
        }

        DispatchQueue.main.async {
            let didOpen = NSApp.sendAction(
                #selector(NSResponder.showWritingTools(_:)),
                to: nil,
                from: nil
            )
            if !didOpen {
                NSSound.beep()
            }
        }
    }

    private func selectAllTextForWritingToolsIfNeeded() {
        let fullTextSelection = NSRange(location: 0, length: (draftText as NSString).length)
        guard fullTextSelection.length > 0 else { return }

        let itemType: ItemType = item?.itemTypeValue ?? .text
        switch itemType {
        case .code:
            if let existingSelection = codeSelectionRange,
                ItemEditorAITextEditing.selectedText(in: draftText, range: existingSelection) != nil
            {
                return
            }

            guard let fullRange = Range(fullTextSelection, in: draftText) else { return }
            codeSelection = TextSelection(range: fullRange)

        case .text, .url, .richText:
            if let existingSelection = richTextSelection,
                ItemEditorAITextEditing.selectedText(in: draftText, range: existingSelection) != nil
            {
                return
            }

            richTextSelection = fullTextSelection

        default:
            break
        }
    }

    private func applyAppleIntelligencePreview(_ preview: ItemEditorAppleIntelligencePreview) {
        do {
            draftText = try ItemEditorAITextEditing.applyReplacement(
                to: draftText,
                replacementText: preview.transformedText,
                target: preview.target
            )
            let isRichText = item?.itemTypeValue == .richText
            if isRichText {
                draftAttributedText = NSAttributedString(
                    string: draftText,
                    attributes: [.font: NSFont.systemFont(ofSize: 16)]
                )
            } else {
                draftAttributedText = nil
            }
            appleIntelligenceError = nil
            appleIntelligencePreview = nil
        } catch {
            appleIntelligenceError =
                "Couldn’t apply generated text because the selection changed. Run the action again."
            NSSound.beep()
        }
    }

    @ViewBuilder
    private func appleIntelligencePreviewSheet(for preview: ItemEditorAppleIntelligencePreview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(preview.action.title) Preview")
                .font(.system(size: 16, weight: .semibold))

            GroupBox("Original") {
                ScrollView {
                    Text(preview.target.sourceText)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                }
                .frame(minHeight: 110, maxHeight: 170)
            }

            GroupBox("Suggestion") {
                ScrollView {
                    Text(preview.transformedText)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                }
                .frame(minHeight: 110, maxHeight: 200)
            }

            HStack {
                Button("Keep Original") {
                    appleIntelligencePreview = nil
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Replace Text") {
                    applyAppleIntelligencePreview(preview)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 560)
    }

    private func appleIntelligenceErrorMessage(for error: AppleIntelligenceTextTransformationError)
        -> String
    {
        switch error {
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "Apple Intelligence isn’t available on this Mac."
            case .appleIntelligenceNotEnabled:
                return "Turn on Apple Intelligence in System Settings to use this feature."
            case .modelNotReady:
                return "Apple Intelligence is still preparing. Try again shortly."
            case .unsupportedLocale:
                return "Apple Intelligence doesn’t currently support this locale."
            }
        case .emptyInput:
            return "No text available for Apple Intelligence."
        case .emptyOutput:
            return "Apple Intelligence returned an empty result. Try again."
        case .generationFailed:
            return "Apple Intelligence couldn’t transform the text right now. Try again."
        }
    }

    private static func nsRange(from selection: TextSelection?, in text: String) -> NSRange? {
        guard let selection else { return nil }
        switch selection.indices {
        case .selection(let range):
            return NSRange(range, in: text)
        case .multiSelection(let ranges):
            guard let firstRange = ranges.ranges.first else { return nil }
            return NSRange(firstRange, in: text)
        @unknown default:
            return nil
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Group {
                if let item = item {
                    switch item.itemTypeValue {
                    case .text, .richText, .code, .url, .color:
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 11, weight: .medium))
                            Text(ItemEditorTextStats(text: draftText).label)
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
                } else {
                    // For new text items
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11, weight: .medium))
                        Text(ItemEditorTextStats(text: draftText).label)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.60))
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                ItemEditorKeyboardHint(key: "⎋", label: "Cancel")
                if supportsEditing {
                    ItemEditorKeyboardHint(key: "⌘↩", label: "Save")
                }
            }
        }
    }

    private var supportsTextEditing: Bool {
        guard let item = item else { return true }
        switch item.itemTypeValue {
        case .text, .richText, .code, .url, .color:
            return true
        default:
            return false
        }
    }

    private var supportsEditing: Bool {
        guard let item = item else { return true }
        switch item.itemTypeValue {
        case .text, .richText, .code, .url, .color, .file, .image:
            return true
        default:
            return false
        }
    }

    private var editorFont: Font {
        if let item = item {
            return item.itemTypeValue == .code
                ? .system(size: 16, weight: .regular, design: .monospaced)
                : .system(size: 16)
        }
        return .system(size: 16)
    }

    private func applyFormatting(_ type: TextFormattingType) {
        NotificationCenter.default.post(
            name: .applyTextFormatting,
            object: nil,
            userInfo: ["type": type]
        )
    }

    // MARK: - New Text Item Views

    private var newTextToolbar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
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

                Text("New Text Item")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.90))

                Spacer(minLength: 0)

                Button {
                    handleSave()
                } label: {
                    Text("Save to Clipboard")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(
                                    !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ? Color(nsColor: .systemBlue)
                                        : Color.white.opacity(0.20)
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .contentShape(Capsule())
                .keyboardShortcut(.return, modifiers: .command)
            }

            // Text formatting toolbar
            HStack(spacing: 8) {
                ItemEditorTextModifierButton(
                    icon: "bold",
                    isActive: isBold,
                    action: {
                        isBold.toggle()
                        applyFormatting(.bold)
                    }
                )

                ItemEditorTextModifierButton(
                    icon: "italic",
                    isActive: isItalic,
                    action: {
                        isItalic.toggle()
                        applyFormatting(.italic)
                    }
                )

                ItemEditorTextModifierButton(
                    icon: "underline",
                    isActive: isUnderline,
                    action: {
                        isUnderline.toggle()
                        applyFormatting(.underline)
                    }
                )

                ItemEditorTextModifierButton(
                    icon: "strikethrough",
                    isActive: isStrikethrough,
                    action: {
                        isStrikethrough.toggle()
                        applyFormatting(.strikethrough)
                    }
                )

                if shouldShowAppleIntelligenceControl {
                    appleIntelligenceMenu
                }

                Spacer()

                Button {
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

            if let appleIntelligenceError {
                Text(appleIntelligenceError)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var newTextEditorSurface: some View {
        RichTextEditor(
            text: $draftText,
            attributedText: $draftAttributedText,
            selection: $richTextSelection,
            initialAttributedText: nil,
            font: .system(size: 16),
            writingToolsBehavior: .complete,
            allowedWritingToolsResultOptions: [.plainText, .richText, .table, .list],
            onBold: { applyFormatting(.bold) },
            onItalic: { applyFormatting(.italic) },
            onUnderline: { applyFormatting(.underline) },
            onStrikethrough: { applyFormatting(.strikethrough) }
        )
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ItemEditorAppleIntelligencePreview: Identifiable {
    let id = UUID()
    let action: AppleIntelligenceTextAction
    let target: ItemEditorAIResolvedTarget
    let transformedText: String
}

enum RotationDirection {
    case left, right
}
