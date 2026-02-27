import Foundation
import MartenCore

#if canImport(UIKit)
import UIKit
#endif

public enum MartenSourceIdentity {
    public static let bundleID = SourceAppIdentity.martenBundleID
    public static let appName = SourceAppIdentity.martenDisplayName

    public static func sourceAppInfo(iconData: Data? = iconData()) -> SourceAppInfo {
        SourceAppInfo(
            bundleID: bundleID,
            name: appName,
            iconData: iconData
        )
    }

    public static func iconData(for bundles: [Bundle] = [Bundle.main]) -> Data? {
        #if canImport(UIKit)
        for bundle in resolvedIconBundles(from: bundles) {
            if let data = iconData(in: bundle) {
                return data
            }
        }
        return nil
        #else
        return nil
        #endif
    }

    #if canImport(UIKit)
    private static func resolvedIconBundles(from bundles: [Bundle]) -> [Bundle] {
        var resolved: [Bundle] = []
        var seenBundlePaths: Set<String> = []

        func append(_ bundle: Bundle?) {
            guard let bundle else { return }
            let path = bundle.bundleURL.standardizedFileURL.path.lowercased()
            guard seenBundlePaths.insert(path).inserted else { return }
            resolved.append(bundle)
        }

        for bundle in bundles {
            append(bundle)
            append(containingAppBundle(for: bundle))
        }

        append(Bundle.main)
        append(containingAppBundle(for: Bundle.main))

        for bundle in Bundle.allFrameworks {
            append(bundle)
        }
        for bundle in Bundle.allBundles {
            append(bundle)
            append(containingAppBundle(for: bundle))
        }

        return resolved
    }

    private static func containingAppBundle(for bundle: Bundle) -> Bundle? {
        let bundleURL = bundle.bundleURL.standardizedFileURL
        guard bundleURL.pathExtension.lowercased() == "appex" else { return nil }

        let plugInsURL = bundleURL.deletingLastPathComponent()
        let appURL = plugInsURL.deletingLastPathComponent()
        guard appURL.pathExtension.lowercased() == "app" else { return nil }

        return Bundle(url: appURL)
    }

    private static func iconData(in bundle: Bundle) -> Data? {
        let iconFileNames = iconNames(from: bundle)
        let candidates = iconNameCandidates(from: iconFileNames)

        for candidate in candidates {
            if let data = imageData(named: candidate, in: bundle) {
                return data
            }
        }

        return nil
    }

    private static func iconNames(from bundle: Bundle) -> [String] {
        guard
            let icons = bundle.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
            let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let iconFiles = primary["CFBundleIconFiles"] as? [String]
        else {
            return []
        }

        return iconFiles.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func iconNameCandidates(from iconFileNames: [String]) -> [String] {
        var candidates: [String] = []

        func append(_ value: String) {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return }
            guard !candidates.contains(normalized) else { return }
            candidates.append(normalized)
        }

        for name in iconFileNames.reversed() {
            append(name)
            append("\(name)60x60")
            append("\(name)60x60@2x")
            append("\(name)76x76")
            append("\(name)76x76@2x~ipad")
            append("\(name)83.5x83.5")
            append("\(name)83.5x83.5@2x~ipad")
            append("\(name)1024")
        }

        [
            "Alpha60x60@2x",
            "Alpha76x76@2x~ipad",
            "AppIcon60x60@2x",
            "AppIcon76x76@2x~ipad",
            "AppIcon83.5x83.5@2x~ipad",
            "AppIcon",
        ].forEach(append)

        return candidates
    }

    private static func imageData(named name: String, in bundle: Bundle) -> Data? {
        if let image = UIImage(named: name, in: bundle, compatibleWith: nil),
            let pngData = image.pngData(),
            !pngData.isEmpty
        {
            return pngData
        }

        let directFileNames = [name, "\(name).png"]
        for fileName in directFileNames {
            guard let path = bundle.path(forResource: fileName, ofType: nil) else { continue }
            guard let rawData = try? Data(contentsOf: URL(fileURLWithPath: path)), !rawData.isEmpty else { continue }
            if let image = UIImage(data: rawData),
                let pngData = image.pngData(),
                !pngData.isEmpty
            {
                return pngData
            }
            return rawData
        }

        if let path = bundle.path(forResource: name, ofType: "png"),
            let rawData = try? Data(contentsOf: URL(fileURLWithPath: path)),
            !rawData.isEmpty
        {
            if let image = UIImage(data: rawData),
                let pngData = image.pngData(),
                !pngData.isEmpty
            {
                return pngData
            }
            return rawData
        }

        return nil
    }
    #endif
}
