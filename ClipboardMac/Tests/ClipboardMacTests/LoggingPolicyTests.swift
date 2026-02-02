import Foundation
import XCTest

final class LoggingPolicyTests: XCTestCase {
    func testNoPrintInProductionTargets() throws {
        let root = try repositoryRoot()
        let paths = [
            root.appendingPathComponent("ClipboardMac/Sources/ClipboardMacApp"),
            root.appendingPathComponent("ClipboardMac/Sources/ClipboardMacServices"),
            root.appendingPathComponent("ClipboardCore/Sources"),
        ]

        let swiftFiles = try paths.flatMap { try swiftSourceFiles(in: $0) }
        let violations = try swiftFiles.compactMap { file -> String? in
            let text = try String(contentsOf: file, encoding: .utf8)
            return text.contains("print(") ? file.path : nil
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Found print() usage in production sources:\n\(violations.joined(separator: "\n"))"
        )
    }

    func testNoPublicPrivacyForSensitiveLogValues() throws {
        let root = try repositoryRoot()
        let paths = [
            root.appendingPathComponent("ClipboardMac/Sources/ClipboardMacApp"),
            root.appendingPathComponent("ClipboardMac/Sources/ClipboardMacServices"),
            root.appendingPathComponent("ClipboardCore/Sources"),
        ]

        let denyTokens = [
            "error.localizedDescription",
            "primaryText",
            "newText",
            "fileName",
            "newFileName",
            "url",
            ".path",
        ]

        let swiftFiles = try paths.flatMap { try swiftSourceFiles(in: $0) }
        var violations: [String] = []

        for file in swiftFiles {
            let lines = try String(contentsOf: file, encoding: .utf8).split(
                separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() {
                guard line.contains("privacy:") && line.contains(".public") else { continue }
                if denyTokens.contains(where: { line.contains($0) }) {
                    violations.append(
                        "\(file.path):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Found privacy: .public on potentially sensitive values:\n\(violations.joined(separator: "\n"))"
        )
    }
}

private func repositoryRoot() throws -> URL {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<20 {
        let candidate = url.deletingLastPathComponent()
        let docs = candidate.appendingPathComponent("docs")
        let mac = candidate.appendingPathComponent("ClipboardMac")
        let core = candidate.appendingPathComponent("ClipboardCore")
        if FileManager.default.fileExists(atPath: docs.path),
            FileManager.default.fileExists(atPath: mac.path),
            FileManager.default.fileExists(atPath: core.path)
        {
            return candidate
        }
        url = candidate
    }
    throw NSError(domain: "LoggingPolicyTests", code: 1)
}

private func swiftSourceFiles(in directory: URL) throws -> [URL] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    )

    var files: [URL] = []
    while let fileURL = enumerator?.nextObject() as? URL {
        guard fileURL.pathExtension == "swift" else { continue }
        files.append(fileURL)
    }
    return files
}
