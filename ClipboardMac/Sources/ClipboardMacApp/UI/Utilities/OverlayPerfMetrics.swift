import Foundation

#if DEBUG
import CoreVideo
import SwiftUI

@MainActor
final class OverlayPerfMetrics: ObservableObject {
    static let shared = OverlayPerfMetrics()

    struct OpSummary: Identifiable {
        let id: String
        let count: Int
        let avgMs: Double
        let maxMs: Double
        let lastMs: Double
    }

    @Published private(set) var fps: Double = 0
    @Published private(set) var avgFrameMs: Double = 0
    @Published private(set) var worstFrameMs: Double = 0
    @Published private(set) var residentMB: Double = 0
    @Published private(set) var topOps: [OpSummary] = []

    private var ops: [String: RollingOpStats] = [:]
    private var frameStats = RollingFrameStats(maxSamples: 240)
    private var refreshTimer: Timer?

    func start() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPublishedValues()
            }
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func recordOperation(name: String, durationNs: UInt64) {
        var stats = ops[name] ?? RollingOpStats(maxSamples: 200)
        stats.add(durationNs)
        ops[name] = stats
    }

    func recordFrame(deltaSeconds: Double) {
        frameStats.add(deltaSeconds)
    }

    private func refreshPublishedValues() {
        let frame = frameStats.snapshot()
        fps = frame.fps
        avgFrameMs = frame.avgMs
        worstFrameMs = frame.maxMs
        residentMB = MemoryFootprint.residentMB()

        let summaries: [OpSummary] = ops.map { key, value in
            let snap = value.snapshot()
            return OpSummary(
                id: key,
                count: snap.count,
                avgMs: snap.avgMs,
                maxMs: snap.maxMs,
                lastMs: snap.lastMs
            )
        }
        topOps = summaries
            .sorted { $0.avgMs > $1.avgMs }
            .prefix(8)
            .map { $0 }
    }
}

private struct RollingOpStats {
    private let maxSamples: Int
    private var samples: [UInt64] = []
    private var last: UInt64 = 0
    private(set) var count: Int = 0

    init(maxSamples: Int) {
        self.maxSamples = maxSamples
        self.samples.reserveCapacity(maxSamples)
    }

    mutating func add(_ ns: UInt64) {
        count += 1
        last = ns
        samples.append(ns)
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
    }

    func snapshot() -> (count: Int, avgMs: Double, maxMs: Double, lastMs: Double) {
        guard !samples.isEmpty else { return (count, 0, 0, Double(last) / 1_000_000) }
        let total = samples.reduce(UInt64(0), +)
        let maxNs = samples.max() ?? 0
        let avg = Double(total) / Double(samples.count)
        return (
            count,
            avg / 1_000_000,
            Double(maxNs) / 1_000_000,
            Double(last) / 1_000_000
        )
    }
}

private struct RollingFrameStats {
    private let maxSamples: Int
    private var samples: [Double] = []

    init(maxSamples: Int) {
        self.maxSamples = maxSamples
        self.samples.reserveCapacity(maxSamples)
    }

    mutating func add(_ deltaSeconds: Double) {
        guard deltaSeconds > 0 else { return }
        samples.append(deltaSeconds)
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
    }

    func snapshot() -> (fps: Double, avgMs: Double, maxMs: Double) {
        guard !samples.isEmpty else { return (0, 0, 0) }
        let avg = samples.reduce(0, +) / Double(samples.count)
        let maxVal = samples.max() ?? 0
        return (
            avg > 0 ? (1.0 / avg) : 0,
            avg * 1000,
            maxVal * 1000
        )
    }
}
#endif

