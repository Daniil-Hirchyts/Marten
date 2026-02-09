import MartenCore
import SwiftUI

// MARK: - Display Mode

/// Display mode for the sync status indicator.
public enum SyncStatusDisplayMode {
    /// Compact mode: icon only with tooltip.
    case compact
    /// Expanded mode: icon, status text, and details.
    case expanded
}

// MARK: - Sync Status Indicator

/// A SwiftUI view that displays the current iCloud sync status.
///
/// The indicator shows:
/// - Current status icon (idle, syncing, synced, error)
/// - Animated icon when syncing
/// - Last sync timestamp ("Synced 2 minutes ago")
/// - Error message when an error occurs
/// - Sync progress when syncing
public struct SyncStatusIndicator<Coordinator: SyncCoordinating & ObservableObject>: View {
    @ObservedObject private var coordinator: Coordinator
    private let displayMode: SyncStatusDisplayMode

    @State private var isAnimating = false

    public init(coordinator: Coordinator, displayMode: SyncStatusDisplayMode = .expanded) {
        self._coordinator = ObservedObject(wrappedValue: coordinator)
        self.displayMode = displayMode
    }

    public var body: some View {
        switch displayMode {
        case .compact:
            compactView
        case .expanded:
            expandedView
        }
    }

    // MARK: - Compact View

    @ViewBuilder
    private var compactView: some View {
        statusIcon
            .help(statusTooltip)
            .accessibilityIdentifier("settings.status.sync")
            .accessibilityLabel("iCloud sync status")
            .accessibilityValue(statusAccessibilityValue)
    }

    // MARK: - Expanded View

    @ViewBuilder
    private var expandedView: some View {
        HStack(spacing: 8) {
            statusIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                if let detailText = statusDetailText {
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.status.sync")
        .accessibilityLabel("iCloud sync status")
        .accessibilityValue(statusAccessibilityValue)
    }

    // MARK: - Status Icon

    @ViewBuilder
    private var statusIcon: some View {
        Image(systemName: statusIconName)
            .font(.system(size: 16))
            .foregroundStyle(statusColor)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .animation(
                coordinator.status == .syncing
                    ? Animation.linear(duration: 1.0).repeatForever(autoreverses: false)
                    : .default,
                value: isAnimating
            )
            .onChange(of: coordinator.status) { _, newStatus in
                isAnimating = (newStatus == .syncing)
            }
            .onAppear {
                isAnimating = (coordinator.status == .syncing)
            }
    }

    // MARK: - Computed Properties

    private var statusIconName: String {
        switch coordinator.status {
        case .idle:
            return "arrow.triangle.2.circlepath"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .synced:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch coordinator.status {
        case .idle:
            return .secondary
        case .syncing:
            return .blue
        case .synced:
            return .green
        case .error:
            return .red
        }
    }

    private var statusText: String {
        switch coordinator.status {
        case .idle:
            return "Sync Idle"
        case .syncing:
            return "Syncing..."
        case .synced:
            return "Synced"
        case .error(let error):
            return error.requiresUserAction ? "Action Required" : "Sync Error"
        }
    }

    private var statusDetailText: String? {
        switch coordinator.status {
        case .idle:
            return lastSyncText
        case .syncing:
            return syncProgressText
        case .synced:
            return lastSyncText
        case .error(let error):
            return error.localizedDescription
        }
    }

    private var statusTooltip: String {
        var tooltip = statusText
        if let detail = statusDetailText {
            tooltip += "\n\(detail)"
        }
        return tooltip
    }

    private var statusAccessibilityValue: String {
        var value = statusText
        if let detail = statusDetailText {
            value += ", \(detail)"
        }
        return value
    }

    private var syncProgressText: String? {
        let progress = coordinator.progress
        let total = progress.itemsQueued
        let completed = progress.itemsUploaded + progress.itemsDownloaded

        guard total > 0 else { return nil }
        return "\(completed) of \(total) items"
    }

    private var lastSyncText: String? {
        guard let lastSync = coordinator.lastSyncDate else { return nil }
        return RelativeTimeFormatter.format(lastSync)
    }
}

// MARK: - Relative Time Formatter

/// Formats dates as relative time strings ("2 minutes ago", "Just now", etc.).
public enum RelativeTimeFormatter {
    /// Formats a date as a relative time string.
    ///
    /// - Parameter date: The date to format.
    /// - Returns: A human-readable relative time string.
    public static func format(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        guard interval >= 0 else {
            return "Just now"
        }

        let seconds = Int(interval)
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24

        if seconds < 60 {
            return "Just now"
        } else if minutes == 1 {
            return "1 minute ago"
        } else if minutes < 60 {
            return "\(minutes) minutes ago"
        } else if hours == 1 {
            return "1 hour ago"
        } else if hours < 24 {
            return "\(hours) hours ago"
        } else if days == 1 {
            return "Yesterday"
        } else {
            return "\(days) days ago"
        }
    }
}

// MARK: - Sync Status View (Convenience)

/// A concrete SyncStatusIndicator using SyncCoordinator.
public struct SyncStatusView: View {
    @ObservedObject private var coordinator: SyncCoordinator
    private let displayMode: SyncStatusDisplayMode

    public init(coordinator: SyncCoordinator, displayMode: SyncStatusDisplayMode = .expanded) {
        self._coordinator = ObservedObject(wrappedValue: coordinator)
        self.displayMode = displayMode
    }

    public var body: some View {
        SyncStatusIndicator(coordinator: coordinator, displayMode: displayMode)
    }
}
