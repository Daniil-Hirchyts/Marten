import AppKit
import ClipboardCore
import ClipboardMacServices
import Darwin
import Foundation

private struct ValidationResult {
    let latencySamples: [TimeInterval]
    let feedbackLoopSuppressed: Bool
    let cpuIdlePercent: Double
}

private struct Phase2ValidationResult {
    let searchLatencySamplesMs: [Double]
    let captureThroughputItemsPerSec: Double
}

private final class ValidationRunner {
    private let pasteboard = NSPasteboard.general
    private let monitor = PasteboardMonitor()
    private var lastDetectionTime: Date?
    private var detectionCount = 0

    func run() {
        let originalString = pasteboard.string(forType: .string)
        defer {
            restorePasteboard(originalString)
        }

        monitor.onClipboardChange = { [weak self] _ in
            self?.lastDetectionTime = Date()
            self?.detectionCount += 1
        }
        monitor.start()

        let result = ValidationResult(
            latencySamples: measureLatency(trials: 5),
            feedbackLoopSuppressed: testFeedbackLoopSuppression(),
            cpuIdlePercent: measureCPUIdlePercent(duration: 5)
        )

        let phase2Result = Phase2ValidationResult(
            searchLatencySamplesMs: measureSearchLatency(samples: 5, itemCount: 1000),
            captureThroughputItemsPerSec: measureCaptureThroughput(itemCount: 500)
        )

        monitor.stop()
        report(result, phase2Result: phase2Result)
    }

    private func measureLatency(trials: Int) -> [TimeInterval] {
        var samples: [TimeInterval] = []
        samples.reserveCapacity(trials)

        for index in 0..<trials {
            lastDetectionTime = nil
            let token = "PasteValidation-\(UUID().uuidString.prefix(8))\(index)"
            let start = Date()
            writePasteboardString(token)

            let detected = runUntil(timeout: 2.0) { [weak self] in
                self?.lastDetectionTime != nil
            }

            if detected, let detectedAt = lastDetectionTime {
                samples.append(detectedAt.timeIntervalSince(start))
            } else {
                samples.append(2.0)
            }
        }

        return samples
    }

    private func testFeedbackLoopSuppression() -> Bool {
        detectionCount = 0
        monitor.suppressNextChange()
        writePasteboardString("PasteValidation-FeedbackLoop")

        let detected = runUntil(timeout: 1.0) { [weak self] in
            (self?.detectionCount ?? 0) > 0
        }

        return !detected
    }

    private func measureCPUIdlePercent(duration: TimeInterval) -> Double {
        let startCPU = processCPUSeconds()
        let startWall = Date()
        let deadline = startWall.addingTimeInterval(duration)

        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        let cpuDelta = processCPUSeconds() - startCPU
        let wallDelta = max(Date().timeIntervalSince(startWall), 0.0001)
        return (cpuDelta / wallDelta) * 100.0
    }

    private func processCPUSeconds() -> TimeInterval {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let user = TimeInterval(usage.ru_utime.tv_sec) + TimeInterval(usage.ru_utime.tv_usec) / 1_000_000
        let system = TimeInterval(usage.ru_stime.tv_sec) + TimeInterval(usage.ru_stime.tv_usec) / 1_000_000
        return user + system
    }

    private func measureSearchLatency(samples: Int, itemCount: Int) -> [Double] {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let storeURL = tempDir.appendingPathComponent("ClipboardPerf.sqlite")
        let persistence = PersistenceController(inMemory: false, storeURL: storeURL)
        let assetStore = AssetStore(baseURL: tempDir.appendingPathComponent("Assets", isDirectory: true))
        let store = ClipItemStore(persistence: persistence, assetStore: assetStore)

        for index in 0..<itemCount {
            let text = index.isMultiple(of: 25) ? "needle \(index)" : "item \(index)"
            let payload = ClipItemPayload(
                representations: [ClipRepresentationPayload.plainText(text)],
                primaryText: text,
                itemType: .text
            )
            _ = try? store.createItem(payload: payload)
        }

        var samplesMs: [Double] = []
        for _ in 0..<samples {
            let start = CFAbsoluteTimeGetCurrent()
            _ = try? store.searchItems(query: "needle", limit: 100)
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            samplesMs.append(elapsedMs)
        }

        try? FileManager.default.removeItem(at: tempDir)
        return samplesMs
    }

    private func measureCaptureThroughput(itemCount: Int) -> Double {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let storeURL = tempDir.appendingPathComponent("ClipboardCapturePerf.sqlite")
        let persistence = PersistenceController(inMemory: false, storeURL: storeURL)
        let assetStore = AssetStore(baseURL: tempDir.appendingPathComponent("Assets", isDirectory: true))
        let store = ClipItemStore(persistence: persistence, assetStore: assetStore)

        let start = CFAbsoluteTimeGetCurrent()
        for index in 0..<itemCount {
            let text = "capture-\(index)-\(UUID().uuidString.prefix(6))"
            let payload = ClipItemPayload(
                representations: [ClipRepresentationPayload.plainText(text)],
                primaryText: text,
                itemType: .text
            )
            _ = try? store.createItem(payload: payload)
        }
        let elapsed = max(CFAbsoluteTimeGetCurrent() - start, 0.0001)

        try? FileManager.default.removeItem(at: tempDir)
        return Double(itemCount) / elapsed
    }

    private func runUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    private func writePasteboardString(_ value: String) {
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private func restorePasteboard(_ originalString: String?) {
        if let originalString {
            writePasteboardString(originalString)
        } else {
            pasteboard.clearContents()
        }
    }

    private func report(_ result: ValidationResult, phase2Result: Phase2ValidationResult) {
        let avgLatency = result.latencySamples.reduce(0, +) / Double(result.latencySamples.count)
        let maxLatency = result.latencySamples.max() ?? 0

        print("Phase 1 Validation Results")
        print("- Pasteboard latency samples (s): \(result.latencySamples.map { String(format: "%.3f", $0) }.joined(separator: ", "))")
        print(String(format: "- Pasteboard latency avg: %.3fs, max: %.3fs", avgLatency, maxLatency))
        print("- Feedback loop suppression: \(result.feedbackLoopSuppressed ? "PASS" : "FAIL")")
        print(String(format: "- CPU idle usage: %.2f%%", result.cpuIdlePercent))
        print("")

        let avgSearch = phase2Result.searchLatencySamplesMs.reduce(0, +) / Double(phase2Result.searchLatencySamplesMs.count)
        let maxSearch = phase2Result.searchLatencySamplesMs.max() ?? 0
        print("Phase 2 Validation Results")
        print("- Search latency samples (ms): \(phase2Result.searchLatencySamplesMs.map { String(format: "%.1f", $0) }.joined(separator: ", "))")
        print(String(format: "- Search latency avg: %.1fms, max: %.1fms", avgSearch, maxSearch))
        print(String(format: "- Capture throughput: %.1f items/sec", phase2Result.captureThroughputItemsPerSec))
        print("- UI rendering: not benchmarked (manual verification pending)")
        print("Note: Pasteboard string content was restored at the end of the run.")
    }
}

private let runner = ValidationRunner()
runner.run()
