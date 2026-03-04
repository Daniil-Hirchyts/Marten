import AppKit
import MartenCore
import MartenMacServices
import OSLog
import SwiftUI

enum ItemEditorMode {
    case edit
    case createNew
}

@MainActor
struct ItemEditorContentView: View {
    let item: ClipItem?
    let onCancel: () -> Void
    let onSave: (String) -> Void
    let mode: ItemEditorMode

    let clipItemEditor: any ClipItemEditing
    let appleIntelligence: any AppleIntelligenceTextTransforming

    @State var draftText: String
    @State var isBold = false
    @State var isItalic = false
    @State var isUnderline = false
    @State var isStrikethrough = false
    @State var fileName: String
    @State var rotationAngle: Angle = .zero
    @State var loadedImage: NSImage?
    @State var originalImage: NSImage?
    @State var loadedFileIcon: NSImage?
    @State var initialRichTextContent: NSAttributedString?
    @State var draftAttributedText: NSAttributedString?
    @State var richTextSelection: NSRange?
    @State var codeSelection: TextSelection?
    @State var appleIntelligenceAvailability: AppleIntelligenceAvailability = .unavailable(.modelNotReady)
    @State var appleIntelligenceTask: Task<Void, Never>?
    @State var appleIntelligenceError: String?
    @State var appleIntelligencePreview: ItemEditorAppleIntelligencePreview?

    @FocusState var isFocused: Bool

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
        } else if let item {
            let initialRichText = item.styledTextContentWithoutTextColor
            _initialRichTextContent = State(initialValue: initialRichText)
            _draftAttributedText = State(initialValue: initialRichText)
            _draftText = State(
                initialValue: initialRichText?.string ?? item.plainTextContent ?? item.primaryText ?? ""
            )

            if item.itemTypeValue == .file {
                _fileName = State(initialValue: item.managedFileDisplayName ?? "File")
            } else if item.itemTypeValue == .image {
                if let customTitle = item.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !customTitle.isEmpty
                {
                    _fileName = State(initialValue: customTitle)
                } else if let path = ItemEditorHelpers.fileURLPath(from: item) {
                    _fileName = State(initialValue: URL(fileURLWithPath: path).lastPathComponent)
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

    var body: some View {
        VStack(spacing: 0) {
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .toolbar { toolbarContent }
        .onAppear { handleAppear() }
        .onDisappear { handleDisappear() }
        .onReceive(NotificationCenter.default.publisher(for: .textFormattingDidChange)) { notification in
            if let isBoldValue = notification.userInfo?["isBold"] as? Bool {
                isBold = isBoldValue
            }
            if let isItalicValue = notification.userInfo?["isItalic"] as? Bool {
                isItalic = isItalicValue
            }
            if let isUnderlineValue = notification.userInfo?["isUnderline"] as? Bool {
                isUnderline = isUnderlineValue
            }
            if let isStrikethroughValue = notification.userInfo?["isStrikethrough"] as? Bool {
                isStrikethrough = isStrikethroughValue
            }
        }
        .sheet(item: $appleIntelligencePreview) { preview in
            appleIntelligencePreviewSheet(for: preview)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {

        // Center: type-specific controls
        if supportsTextEditing {
            ToolbarItemGroup(placement: .principal) {
                textFormattingControls
            }
        }

        if let item, item.itemTypeValue == .color {
            ToolbarItemGroup(placement: .principal) {
                colorControls
            }
        }

        if let item, item.itemTypeValue == .image {
            ToolbarItemGroup(placement: .principal) {
                imageControls
            }
        }

        if let item, item.itemTypeValue == .file {
            ToolbarItemGroup(placement: .principal) {
                fileControls
            }
        }
    }

    private var textFormattingControls: some View {
        HStack(spacing: 2) {
            // Bold/Italic/Underline/Strikethrough only for text, richText, url, color — NOT for code
            if showsTextModifierButtons {
                toolbarButton(icon: "bold", isActive: isBold) { applyFormatting(.bold) }
                toolbarButton(icon: "italic", isActive: isItalic) { applyFormatting(.italic) }
                toolbarButton(icon: "underline", isActive: isUnderline) { applyFormatting(.underline) }
                toolbarButton(icon: "strikethrough", isActive: isStrikethrough) { applyFormatting(.strikethrough) }

                Divider()
                    .frame(height: 18)
                    .padding(.horizontal, 4)

                toolbarButton(icon: "textformat", isActive: false) { applyFormatting(.clearFormatting) }
                    .help("Clear Formatting")
            }

            // Apple Intelligence — shown for all text/code types when available
            if shouldShowAppleIntelligenceControl {
                if showsTextModifierButtons {
                    Divider()
                        .frame(height: 18)
                        .padding(.horizontal, 4)
                }
                appleIntelligenceMenu
            }

            // Copy button — shown for all text types including code
            Divider()
                .frame(height: 18)
                .padding(.horizontal, 4)

            Button(action: { copyPlainTextToMarten() }) {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy")
        }
    }

    private var imageControls: some View {
        HStack(spacing: 2) {
            Button(action: { rotateImage(direction: .left) }) {
                Image(systemName: "rotate.left")
            }
            .help("Rotate Left")

            Button(action: { rotateImage(direction: .right) }) {
                Image(systemName: "rotate.right")
            }
            .help("Rotate Right")

            Divider()
                .frame(height: 18)
                .padding(.horizontal, 4)

            Button(action: { copyImageToMarten() }) {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy Image")

            Button(action: { saveImageToFile() }) {
                Image(systemName: "square.and.arrow.down")
            }
            .help("Save As…")
        }
    }

    private var fileControls: some View {
        HStack(spacing: 2) {
            Button(action: { revealInFinder() }) {
                Image(systemName: "folder")
            }
            .help("Show in Finder")

            Button(action: { openFile() }) {
                Image(systemName: "arrow.up.forward.app")
            }
            .help("Open")

            Divider()
                .frame(height: 18)
                .padding(.horizontal, 4)

            Button(action: { copyFilePath() }) {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy Path")
        }
    }

    private var colorControls: some View {
        HStack(spacing: 2) {
            Button(action: {
                let hex = ColorEditorView.normalizeHex(draftText) ?? draftText
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(hex, forType: .string)
            }) {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy Hex Value")
        }
    }

    private func toolbarButton(
        icon: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .foregroundStyle(isActive ? Color.accentColor : .primary)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        if let item {
            switch item.itemTypeValue {
            case .file:
                FileInfoView(
                    byteCount: item.byteCount,
                    fileIcon: loadedFileIcon,
                    fileName: $fileName
                )
            case .image:
                ImageEditorView(
                    image: loadedImage,
                    rotationAngle: rotationAngle
                )
            case .color:
                ColorEditorView(hexText: $draftText)
            default:
                TextEditorView(
                    itemType: item.itemTypeValue,
                    initialAttributedText: initialRichTextContent,
                    font: editorFont,
                    writingToolsBehavior: richTextEditorWritingToolsBehavior,
                    allowedWritingToolsResultOptions: richTextEditorWritingToolsResultOptions,
                    onBold: { applyFormatting(.bold) },
                    onItalic: { applyFormatting(.italic) },
                    onUnderline: { applyFormatting(.underline) },
                    onStrikethrough: { applyFormatting(.strikethrough) },
                    text: $draftText,
                    attributedText: $draftAttributedText,
                    richTextSelection: $richTextSelection,
                    codeSelection: $codeSelection,
                    isFocused: $isFocused
                )
            }
        } else {
            TextEditorView(
                itemType: .text,
                initialAttributedText: nil,
                font: .system(size: 16),
                writingToolsBehavior: .complete,
                allowedWritingToolsResultOptions: [.plainText, .richText, .table, .list],
                onBold: { applyFormatting(.bold) },
                onItalic: { applyFormatting(.italic) },
                onUnderline: { applyFormatting(.underline) },
                onStrikethrough: { applyFormatting(.strikethrough) },
                text: $draftText,
                attributedText: $draftAttributedText,
                richTextSelection: $richTextSelection,
                codeSelection: $codeSelection,
                isFocused: $isFocused
            )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            footerLeft
            
            if appleIntelligenceError != nil {
                Text(appleIntelligenceError!)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red.opacity(0.85))
            }
            
            Spacer(minLength: 0)
            
            footerRight
        }
    }

    private var footerRight: some View {
        HStack(spacing: 8) {
            Button("Cancel") { onCancel() }
                .keyboardShortcut(.cancelAction)
            
            Button("Save") { handleSave() }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
        }
    }

    @ViewBuilder
    private var footerLeft: some View {
        if let item {
            switch item.itemTypeValue {
            case .text, .richText, .code, .url, .color:
                Text(ItemEditorTextStats(text: draftText).label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            case .image:
                imageFooter
            case .file:
                fileFooter
            default:
                EmptyView()
            }
        } else {
            Text(ItemEditorTextStats(text: draftText).label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var imageFooter: some View {
        HStack(spacing: 12) {
            if let image = loadedImage {
                Text("\(Int(image.size.width))×\(Int(image.size.height))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            if let item, item.byteCount > 0 {
                Text(ItemEditorHelpers.formatFileSize(item.byteCount))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fileFooter: some View {
        HStack(spacing: 12) {
            if let item, item.byteCount > 0 {
                Text(ItemEditorHelpers.formatFileSize(item.byteCount))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Derived State

    var titleText: String {
        mode == .createNew ? "New Text Item" : editorTitle
    }

    var supportsCopyButton: Bool {
        guard let item else { return true }
        return item.itemTypeValue != .code
    }

    var showsTextModifierButtons: Bool {
        guard let item else { return true }
        return item.itemTypeValue != .code
    }

    var canSave: Bool {
        guard let item else {
            return !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        switch item.itemTypeValue {
        case .file, .image:
            return !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return supportsTextEditing
        }
    }

    var editorTitle: String {
        guard let item else { return "New Text Item" }
        switch item.itemTypeValue {
        case .code: return "Edit Code"
        case .url: return "Edit URL"
        case .color: return "Edit Color"
        case .image: return "Edit Image"
        case .file: return "Edit File"
        default: return "Edit Text"
        }
    }

    var supportsTextEditing: Bool {
        guard let item else { return true }
        switch item.itemTypeValue {
        case .text, .richText, .code, .url:
            return true
        default:
            return false
        }
    }

    var supportsEditing: Bool {
        guard let item else { return true }
        switch item.itemTypeValue {
        case .text, .richText, .code, .url, .color, .file, .image:
            return true
        default:
            return false
        }
    }

    var editorFont: Font {
        if let item {
            return item.itemTypeValue == .code
                ? .system(size: 16, weight: .regular, design: .monospaced)
                : .system(size: 16)
        }
        return .system(size: 16)
    }

    var originalFileName: String {
        guard let item else { return "Untitled" }
        if item.itemTypeValue == .file {
            return item.managedFileDisplayName ?? "File"
        } else if item.itemTypeValue == .image {
            if let customTitle = item.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                !customTitle.isEmpty
            {
                return customTitle
            } else if let path = ItemEditorHelpers.fileURLPath(from: item) {
                return URL(fileURLWithPath: path).lastPathComponent
            } else {
                return "image.png"
            }
        }
        return "Untitled"
    }

    // MARK: - Formatting

    func applyFormatting(_ type: TextFormattingType) {
        NotificationCenter.default.post(
            name: .applyTextFormatting,
            object: nil,
            userInfo: ["type": type]
        )
    }
}

// MARK: - Text Stats

struct ItemEditorTextStats: Equatable {
    let characters: Int
    let words: Int
    let lines: Int

    init(text: String) {
        characters = text.count
        words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        lines = max(1, text.split(separator: "\n", omittingEmptySubsequences: false).count)
    }

    var label: String {
        "\(characters) chars  •  \(words) words  •  \(lines) line\(lines == 1 ? "" : "s")"
    }
}
