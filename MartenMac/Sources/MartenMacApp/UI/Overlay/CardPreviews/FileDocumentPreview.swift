import AppKit
import Foundation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct FileDocumentPreview: View {
    let fileURL: URL

    private var fileExtension: String {
        fileURL.pathExtension.lowercased()
    }

    private var fileType: UTType? {
        UTType(filenameExtension: fileExtension)
    }

    private var shouldUsePDFPreview: Bool {
        fileType?.conforms(to: .pdf) == true || fileExtension == "pdf"
    }

    private var shouldUseImagePreview: Bool {
        fileType?.conforms(to: .image) == true
    }

    private var shouldUseTextPreview: Bool {
        if fileType?.conforms(to: .plainText) == true || fileType?.conforms(to: .sourceCode) == true {
            return true
        }

        return Self.textExtensions.contains(fileExtension)
    }

    var body: some View {
        Group {
            if shouldUsePDFPreview {
                PDFFilePreview(fileURL: fileURL)
            } else if shouldUseImagePreview {
                ImageFilePreview(fileURL: fileURL)
            } else if shouldUseTextPreview {
                TextFilePreview(fileURL: fileURL)
            } else {
                FileQuickLookPreview(fileURL: fileURL)
            }
        }
    }

    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "json", "xml", "yaml", "yml", "csv", "tsv", "log",
        "swift", "m", "mm", "h", "hpp", "c", "cpp", "cc", "java", "kt", "js", "jsx",
        "ts", "tsx", "py", "rb", "go", "rs", "php", "sql", "sh", "zsh", "bash"
    ]
}

private struct PDFFilePreview: NSViewRepresentable {
    let fileURL: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView(frame: .zero)
        view.autoScales = true
        view.displaysPageBreaks = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: fileURL)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        guard nsView.document?.documentURL != fileURL else { return }
        nsView.document = PDFDocument(url: fileURL)
    }
}

private struct ImageFilePreview: View {
    let fileURL: URL
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .task(id: fileURL.path) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        if let loaded = NSImage(contentsOf: fileURL) {
            image = loaded
        } else {
            image = nil
        }
    }
}

private struct TextFilePreview: View {
    let fileURL: URL
    @State private var text: String?
    @State private var didTruncate = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(text ?? "Loading preview…")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                if didTruncate {
                    Text("Preview truncated")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: fileURL.path) {
            await loadTextPreview()
        }
    }

    @MainActor
    private func loadTextPreview() async {
        let maxBytes = 200_000

        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            text = "Unable to open file preview."
            didTruncate = false
            return
        }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: maxBytes + 1) else {
            text = "Unable to read file preview."
            didTruncate = false
            return
        }

        didTruncate = data.count > maxBytes
        let previewData = didTruncate ? Data(data.prefix(maxBytes)) : data

        if let decoded = String(data: previewData, encoding: .utf8) {
            text = decoded
            return
        }
        if let decoded = String(data: previewData, encoding: .utf16) {
            text = decoded
            return
        }

        text = "Binary file preview unavailable."
    }
}
