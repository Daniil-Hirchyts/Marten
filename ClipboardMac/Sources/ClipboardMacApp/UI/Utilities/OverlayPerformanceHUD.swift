import SwiftUI

#if DEBUG
struct OverlayPerformanceHUD: View {
    @ObservedObject private var metrics = OverlayPerfMetrics.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                metricPill(title: "FPS", value: String(format: "%.0f", metrics.fps))
                metricPill(title: "Frame", value: String(format: "%.1f ms", metrics.avgFrameMs))
                metricPill(title: "Worst", value: String(format: "%.1f ms", metrics.worstFrameMs))
                metricPill(title: "Mem", value: String(format: "%.0f MB", metrics.residentMB))
            }

            if !metrics.topOps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(metrics.topOps.prefix(5)) { op in
                        HStack(spacing: 8) {
                            Text(op.id)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(String(format: "avg %.2f ms", op.avgMs))
                                .font(.system(size: 11, design: .monospaced))
                            Text(String(format: "max %.2f", op.maxMs))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.62))
        )
        .foregroundStyle(.white)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func metricPill(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
    }
}
#endif

