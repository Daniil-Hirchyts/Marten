import SwiftUI

struct WatchItemRow: View {
    let item: WatchClipSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: item.systemImageName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(contentPreview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer(minLength: 0)

                Text(WatchRelativeTime.short(from: item.modifiedAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .watchCard(prominence: .normal)
    }

    private var contentPreview: String {
        let subtitle = item.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !subtitle.isEmpty {
            return subtitle
        }

        return item.preferredText
    }
}
