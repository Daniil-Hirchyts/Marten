import AppKit
import ClipboardCore
import ClipboardMacServices
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
            let initialRichText = item.itemTypeValue == .richText ? item.styledTextContentWithoutTextColor : nil
            _initialRichTextContent = State(initialValue: initialRichText)
            _draftAttributedText = State(initialValue: initialRichText)
            _draftText = State(initialValue: initialRichText?.string ?? item.primaryText ?? "")

            if item.itemTypeValue == .file, let filePath = item.primaryText {
                _fileName = State(initialValue: URL(fileURLWithPath: filePath).lastPathComponent)
            } else if item.itemTypeValue == .image {
                if let path = ItemEditorHelpers.fileURLPath(from: item) {
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
        editorBody
            .onAppear { handleAppear() }
            .onDisappear { handleDisappear() }
            .sheet(item: $appleIntelligencePreview) { preview in
                appleIntelligencePreviewSheet(for: preview)
            }
    }

    // MARK: - Composed Views

    private var editorBody: AnyView {
        AnyView(
            ZStack {
            VStack(spacing: 0) {
                dragHandle
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                VStack(spacing: 16) {
                    RichTextToolbar(
                        title: titleText,
                        saveTitle: saveTitle,
                        canSave: canSave,
                        showsFormattingControls: showsFormattingControls,
                        showsTextModifierButtons: showsTextModifierButtons,
                        showsAppleIntelligenceControl: shouldShowAppleIntelligenceControl,
                        appleIntelligenceError: appleIntelligenceError,
                        isBold: isBold,
                        isItalic: isItalic,
                        isUnderline: isUnderline,
                        isStrikethrough: isStrikethrough,
                        onCancel: { onCancel() },
                        onSave: { handleSave() },
                        onCopyPlainText: supportsCopyButton ? { copyPlainTextToClipboard() } : nil,
                        onToggleBold: { toggleFormatting(.bold) },
                        onToggleItalic: { toggleFormatting(.italic) },
                        onToggleUnderline: { toggleFormatting(.underline) },
                        onToggleStrikethrough: { toggleFormatting(.strikethrough) },
                        appleIntelligenceControl: AnyView(appleIntelligenceMenu)
                    )

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
                        .foregroundStyle(Color(nsColor: .white).opacity(0.30))
                        .padding(12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { backgroundView }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(nsColor: .white), lineWidth: 1)
                .opacity(0.15)
        }
        .shadow(color: Color(nsColor: .black).opacity(0.3), radius: 30, x: 0, y: 15)
        )
    }

    private var editorSurface: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .white).opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(nsColor: .white).opacity(0.12), lineWidth: 1)
                )

            contentView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var contentView: some View {
        if let item {
            switch item.itemTypeValue {
            case .file:
                FileInfoView(
                    byteCount: item.byteCount,
                    filePath: item.primaryText,
                    fileIcon: loadedFileIcon,
                    onRevealInFinder: { revealInFinder() },
                    onOpen: { openFile() },
                    onCopyPath: { copyFilePath() },
                    fileName: $fileName
                )
            case .image:
                ImageEditorView(
                    byteCount: item.byteCount,
                    image: loadedImage,
                    rotationAngle: rotationAngle,
                    onRotateLeft: { rotateImage(direction: .left) },
                    onRotateRight: { rotateImage(direction: .right) },
                    onCopy: { copyImageToClipboard() },
                    onSaveAs: { saveImageToFile() },
                    fileName: $fileName
                )
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
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .white).opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .white).opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            footerLeft
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                ItemEditorKeyboardHint(key: "⎋", label: "Cancel")
                if supportsEditing {
                    ItemEditorKeyboardHint(key: "⌘↩", label: "Save")
                }
            }
        }
    }

    @ViewBuilder
    private var footerLeft: some View {
        if let item {
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
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11, weight: .medium))
                Text(ItemEditorTextStats(text: draftText).label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.60))
        }
    }

    // MARK: - Shell

    private var backgroundView: AnyView {
        if #available(macOS 26.0, *) {
            AnyView(
                Rectangle()
                    .fill(Color.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20, style: .continuous))
            )
        } else {
            AnyView(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))
        }
    }

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color(nsColor: .white).opacity(0.25))
            .frame(width: 36, height: 5)
    }
}
