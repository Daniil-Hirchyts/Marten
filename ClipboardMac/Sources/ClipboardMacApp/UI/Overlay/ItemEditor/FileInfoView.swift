import AppKit
import SwiftUI

@MainActor
struct FileInfoView: View {
    let byteCount: Int64
    let filePath: String?
    let fileIcon: NSImage?
    let onRevealInFinder: () -> Void
    let onOpen: () -> Void
    let onCopyPath: () -> Void

    @Binding var fileName: String

    private var fileExtension: String? {
        fileName.split(separator: ".").last.map(String.init)
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

    var body: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))

                    VStack(spacing: 20) {
                        if let icon = fileIcon {
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
                    actionButton(icon: "folder", tooltip: "Show in Finder", action: onRevealInFinder)
                    actionButton(icon: "arrow.up.forward.app", tooltip: "Open", action: onOpen)
                    actionButton(icon: "doc.on.doc", tooltip: "Copy Path", action: onCopyPath)
                }
                .padding(12)
            }

            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    if byteCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "doc")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.50))
                            Text(ItemEditorHelpers.formatFileSize(byteCount))
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

    private func actionButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
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
}

