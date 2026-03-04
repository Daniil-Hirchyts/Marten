import AppKit
import MartenCore
import SwiftUI

extension OverlayItemPreview {
    func refreshCachedProperties() {
        cachedProps = CachedItemProperties(item: item)
    }

    func refreshStyledTextPreview() {
        guard let styled = item.styledTextContentWithoutTextColor else {
            styledRichTextPreview = nil
            return
        }

        styledRichTextPreview = try? AttributedString(styled, including: \.appKit)
    }

    func loadAssetsIfNeeded() {
        loadImageIfNeeded()
        loadFileIconIfNeeded()
    }

    func loadImageIfNeeded() {
        guard item.itemTypeValue == .image else {
            image = nil
            return
        }

        let previewItemID = item.objectID
        let sortedRepresentations = (item.representations ?? []).sorted {
            $0.displayOrder < $1.displayOrder
        }
        let fullResolutionImageSources: [(data: Data?, assetRef: UUID?, fileExtension: String?)] =
            sortedRepresentations.compactMap { rep in
                let kind = rep.kindValue
                guard kind == .png || kind == .jpeg || kind == .tiff || kind == .pdf else {
                    return nil
                }
                return (rep.binaryData, rep.assetRef, rep.fileExtension)
            }
        let imageFilePath = filePathFromRepresentations()

        DispatchQueue.global(qos: .userInitiated).async {
            for source in fullResolutionImageSources {
                if let data = source.data, let img = NSImage(data: data) {
                    DispatchQueue.main.async {
                        guard item.objectID == previewItemID else { return }
                        image = img
                    }
                    return
                }

                if let assetRef = source.assetRef,
                    let data = try? AssetStore.shared.load(
                        assetRef: assetRef,
                        fileExtension: source.fileExtension
                    ),
                    let img = NSImage(data: data)
                {
                    DispatchQueue.main.async {
                        guard item.objectID == previewItemID else { return }
                        image = img
                    }
                    return
                }
            }

            if let imageFilePath, let img = NSImage(contentsOfFile: imageFilePath) {
                DispatchQueue.main.async {
                    guard item.objectID == previewItemID else { return }
                    image = img
                }
                return
            }

            DispatchQueue.main.async {
                guard item.objectID == previewItemID else { return }
                image = nil
            }
        }
    }

    func fullResolutionImagePathFromRepresentations() -> String? {
        let sortedRepresentations = (item.representations ?? []).sorted {
            $0.displayOrder < $1.displayOrder
        }

        for rep in sortedRepresentations {
            let kind = rep.kindValue
            guard kind == .png || kind == .jpeg || kind == .tiff || kind == .pdf else {
                continue
            }

            if let assetRef = rep.assetRef,
                let fileURL = AssetStore.shared.existingURLForAsset(
                    assetRef,
                    fileExtension: rep.fileExtension
                )
            {
                return fileURL.path
            }
        }

        return nil
    }

    func loadFileIconIfNeeded() {
        guard item.itemTypeValue == .file, let path = filePathFromRepresentations() else {
            fileIcon = nil
            return
        }
        fileIcon = NSWorkspace.shared.icon(forFile: path)
    }

    func filePathFromRepresentations() -> String? {
        guard let resolvedURL = FileURLAccessResolver.resolvedFileURL(from: item) else {
            return nil
        }
        return resolvedURL.path
    }
}
