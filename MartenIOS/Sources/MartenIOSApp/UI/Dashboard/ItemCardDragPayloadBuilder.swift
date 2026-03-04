import CoreData
import MartenCore
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit

struct ItemCardDragPayloadBuilder {
    func dragItem(for objectID: NSManagedObjectID, item: ClipItem) -> UIDragItem {
        let payload = ItemDragPayload(objectIDs: [objectID])
        let provider = NSItemProvider()

        provider.registerDataRepresentation(forTypeIdentifier: UTType.json.identifier, visibility: .ownProcess) { completion in
            do {
                let data = try JSONEncoder().encode(payload)
                completion(data, nil)
            } catch {
                completion(nil, error)
            }
            return nil
        }

        if let urlString = item.primaryText,
           item.itemTypeValue == .url,
           let url = URL(string: urlString) {
            provider.registerObject(url as NSURL, visibility: .all)
        } else if item.itemTypeValue == .file,
                  let fileURL = try? ManagedFileAccess.exportURL(for: item) {
            provider.registerObject(fileURL as NSURL, visibility: .all)
        } else if item.itemTypeValue == .image {
            registerImageData(for: item, into: provider)
        } else if let text = item.plainTextContent, !text.isEmpty {
            provider.registerObject(text as NSString, visibility: .all)
        }

        let dragItem = UIDragItem(itemProvider: provider)
        dragItem.localObject = objectID
        return dragItem
    }

    /// Registers the original image bytes from `item`'s representation into
    /// `provider` so external drop targets (Photos, Notes, Messages, …) receive
    /// the actual image data rather than a text fallback.
    private func registerImageData(for item: ClipItem, into provider: NSItemProvider) {
        guard let representations = item.representations as? Set<ClipRepresentation> else { return }

        let imageKinds: Set<RepresentationKind> = [.png, .jpeg, .tiff]
        guard let rep = representations
            .filter({ imageKinds.contains($0.kindValue) })
            .sorted(by: { $0.displayOrder < $1.displayOrder })
            .first
        else { return }

        // HEIC/HEIF are stored with .jpeg kind; use fileExtension to pick the right UTType.
        let utType: UTType
        switch rep.fileExtension?.lowercased() {
        case "png":         utType = .png
        case "heic":        utType = .heic
        case "heif":        utType = .heif
        case "tiff", "tif": utType = .tiff
        default:
            switch rep.kindValue {
            case .png:  utType = .png
            case .tiff: utType = .tiff
            default:    utType = .jpeg
            }
        }

        if let assetRef = rep.assetRef,
            let imageURL = AssetStore.shared.existingURLForAsset(
                assetRef,
                fileExtension: rep.fileExtension
            )
        {
            provider.registerDataRepresentation(forTypeIdentifier: utType.identifier, visibility: .all) { completion in
                DispatchQueue.global(qos: .userInitiated).async {
                    if let data = try? Data(contentsOf: imageURL) {
                        completion(data, nil)
                    } else {
                        completion(nil, CocoaError(.fileReadNoSuchFile))
                    }
                }
                return nil
            }
        } else if let binaryData = rep.binaryData, !binaryData.isEmpty {
            let data = binaryData
            provider.registerDataRepresentation(forTypeIdentifier: utType.identifier, visibility: .all) { completion in
                completion(data, nil)
                return nil
            }
        }
    }
}

#endif
