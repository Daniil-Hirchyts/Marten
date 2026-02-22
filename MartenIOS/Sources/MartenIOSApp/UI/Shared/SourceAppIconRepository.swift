import Foundation

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

@MainActor
final class SourceAppIconRepository {
    static let shared = SourceAppIconRepository()

    #if canImport(UIKit)
    private let memoryCache = NSCache<NSString, UIImage>()
    #elseif canImport(AppKit)
    private let memoryCache = NSCache<NSString, NSImage>()
    #endif

    private var inFlight: [String: Task<PlatformImage?, Never>] = [:]
    private let cacheDirectoryURL: URL?

    private init() {
        let fileManager = FileManager.default
        if let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let directory = cachesDirectory.appendingPathComponent("MartenSourceAppIcons", isDirectory: true)
            if !fileManager.fileExists(atPath: directory.path) {
                try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            cacheDirectoryURL = directory
        } else {
            cacheDirectoryURL = nil
        }
    }

    func icon(forBundleID bundleID: String) async -> PlatformImage? {
        let key = bundleID.lowercased()

        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }

        if let cached = loadFromDisk(bundleID: key) {
            memoryCache.setObject(cached, forKey: key as NSString)
            return cached
        }

        if let runningTask = inFlight[key] {
            return await runningTask.value
        }

        let task = Task<PlatformImage?, Never> {
            guard let artworkURL = await Self.lookupArtworkURL(bundleID: key),
                  let image = await Self.downloadImage(from: artworkURL) else {
                return nil
            }
            return image
        }

        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil

        guard let image else { return nil }
        memoryCache.setObject(image, forKey: key as NSString)
        saveToDisk(image: image, bundleID: key)
        return image
    }

    private func fileURL(for bundleID: String) -> URL? {
        guard let cacheDirectoryURL else { return nil }
        let hash = SourceAppIconDescriptor.stableHash(forIdentifier: bundleID)
        return cacheDirectoryURL
            .appendingPathComponent("app-icon-\(hash)")
            .appendingPathExtension("png")
    }

    private func loadFromDisk(bundleID: String) -> PlatformImage? {
        guard let fileURL = fileURL(for: bundleID),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        #if canImport(UIKit)
        return UIImage(data: data)
        #elseif canImport(AppKit)
        return NSImage(data: data)
        #endif
    }

    private func saveToDisk(image: PlatformImage, bundleID: String) {
        guard let fileURL = fileURL(for: bundleID),
              let data = encodedData(from: image) else {
            return
        }

        try? data.write(to: fileURL, options: [.atomic])
    }

    #if canImport(UIKit)
    private func encodedData(from image: UIImage) -> Data? {
        image.pngData()
    }
    #elseif canImport(AppKit)
    private func encodedData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
    }
    #endif

    private struct AppStoreLookupResponse: Decodable {
        let results: [AppStoreLookupResult]
    }

    private struct AppStoreLookupResult: Decodable {
        let artworkUrl512: String?
        let artworkUrl100: String?
        let artworkUrl60: String?
        let artworkUrl30: String?
    }

    private static func lookupArtworkURL(bundleID: String) async -> URL? {
        for endpoint in lookupEndpoints(for: bundleID) {
            guard let data = await fetchData(from: endpoint),
                  let response = try? JSONDecoder().decode(AppStoreLookupResponse.self, from: data) else {
                continue
            }

            for result in response.results {
                for raw in [result.artworkUrl512, result.artworkUrl100, result.artworkUrl60, result.artworkUrl30] {
                    guard let raw else { continue }
                    if let url = normalizedArtworkURL(from: raw) {
                        return url
                    }
                }
            }
        }

        return nil
    }

    private static func lookupEndpoints(for bundleID: String) -> [URL] {
        guard let escapedBundleID = bundleID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }

        let rawEndpoints = [
            "https://itunes.apple.com/lookup?bundleId=\(escapedBundleID)&entity=software",
            "https://itunes.apple.com/lookup?bundleId=\(escapedBundleID)&entity=macSoftware",
        ]

        return rawEndpoints.compactMap(URL.init(string:))
    }

    private static func normalizedArtworkURL(from raw: String) -> URL? {
        guard var components = URLComponents(string: raw) else { return nil }
        if components.scheme == "http" {
            components.scheme = "https"
        }
        return components.url
    }

    private static func fetchData(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 8

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            return nil
        }

        return data
    }

    private static func downloadImage(from url: URL) async -> PlatformImage? {
        guard let data = await fetchData(from: url) else {
            return nil
        }

        #if canImport(UIKit)
        return UIImage(data: data)
        #elseif canImport(AppKit)
        return NSImage(data: data)
        #endif
    }
}
