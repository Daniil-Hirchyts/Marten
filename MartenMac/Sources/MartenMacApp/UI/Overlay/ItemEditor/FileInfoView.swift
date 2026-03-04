import AppKit
import SwiftUI

@MainActor
struct FileInfoView: View {
    let byteCount: Int64
    let fileIcon: NSImage?
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
        VStack(spacing: 20) {
            Spacer()

            if let icon = fileIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
            } else {
                Image(systemName: fileIconSystemName)
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                Text(fileName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if let ext = fileExtension {
                    Text(ext.uppercased())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                        )
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
