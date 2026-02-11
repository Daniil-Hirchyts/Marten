import MartenCore
import SwiftUI

struct DashboardSearchStackView: View {
    @Bindable var searchModel: DashboardSearchModel
    let onOpenItem: (ClipItem) -> Void

    @State private var isShowingFilters = false
    @ScaledMetric(relativeTo: .headline) private var actionButtonSize: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            searchBar
            activeFiltersChips
            suggestedApps
            quickResults
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .sheet(isPresented: $isShowingFilters) {
            DashboardFilterSheet(searchModel: searchModel)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                #if os(iOS)
                TextField("Search", text: $searchModel.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                #else
                TextField("Search", text: $searchModel.query)
                #endif

                if !searchModel.query.isEmpty {
                    Button {
                        searchModel.clearSearchText()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: .rect(cornerRadius: 12))

            Button {
                searchModel.toggleVoiceDictation()
            } label: {
                Image(systemName: searchModel.isVoiceRecording ? "waveform.circle.fill" : "mic.fill")
                    .font(.headline)
                    .frame(width: actionButtonSize, height: actionButtonSize)
            }
            .buttonStyle(.plain)
            .glassButtonFallbackBackground(isHighlighted: searchModel.isVoiceRecording)
            .accessibilityLabel(searchModel.isVoiceRecording ? "Stop voice search" : "Start voice search")

            Button {
                isShowingFilters = true
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.headline)
                    .frame(width: actionButtonSize, height: actionButtonSize)
            }
            .buttonStyle(.plain)
            .glassButtonFallbackBackground(isHighlighted: searchModel.hasActiveFilters)
            .accessibilityLabel("Search filters")
        }
    }

    @ViewBuilder
    private var activeFiltersChips: some View {
        if searchModel.hasActiveFilters {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    if searchModel.dateFilter != .any {
                        filterChip(searchModel.dateFilter.label) {
                            searchModel.dateFilter = .any
                        }
                    }

                    ForEach(Array(searchModel.selectedTypes), id: \.rawValue) { type in
                        filterChip(type.label) {
                            searchModel.toggleType(type)
                        }
                    }

                    ForEach(Array(searchModel.selectedSourceApps), id: \.self) { appID in
                        filterChip(appID) {
                            searchModel.toggleSourceApp(appID)
                        }
                    }

                    ForEach(Array(searchModel.selectedSourceDevices), id: \.hashValue) { device in
                        filterChip(device.label) {
                            searchModel.toggleSourceDevice(device)
                        }
                    }

                    Button("Clear All") {
                        searchModel.clearAllFilters()
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private var suggestedApps: some View {
        if !searchModel.suggestedApps.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(searchModel.suggestedApps) { app in
                        Button {
                            searchModel.toggleSourceApp(app.id)
                        } label: {
                            Text(app.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .glassButtonFallbackBackground(
                            isHighlighted: searchModel.selectedSourceApps.contains(app.id)
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private var quickResults: some View {
        if searchModel.isSearchActive && !searchModel.quickResults.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(searchModel.quickResults, id: \.objectID) { item in
                        Button {
                            onOpenItem(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ItemCardPresentation(item: item).title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)

                                Text(ItemCardPresentation(item: item).footerSource)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(width: 170, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .glassButtonFallbackBackground(isHighlighted: false)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func filterChip(_ title: String, removeAction: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Button {
                removeAction()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Filter: \(title)")
        .accessibilityHint("Double tap to remove filter")
    }
}

private struct DashboardFilterSheet: View {
    @Bindable var searchModel: DashboardSearchModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Date") {
                    ForEach(ClipItemDateFilter.allCases, id: \.rawValue) { filter in
                        Button {
                            searchModel.dateFilter = filter
                        } label: {
                            HStack {
                                Text(filter.label)
                                Spacer()
                                if searchModel.dateFilter == filter {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                Section("Content Type") {
                    ForEach(ItemType.allCases, id: \.rawValue) { type in
                        Button {
                            searchModel.toggleType(type)
                        } label: {
                            HStack {
                                Text(type.label)
                                Spacer()
                                if searchModel.selectedTypes.contains(type) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                Section("Source App") {
                    if searchModel.appOptions.isEmpty {
                        Text("No source apps yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(searchModel.appOptions) { app in
                            Button {
                                searchModel.toggleSourceApp(app.id)
                            } label: {
                                HStack {
                                    Text(app.name)
                                    Spacer()
                                    Text("\(app.count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if searchModel.selectedSourceApps.contains(app.id) {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Source Device") {
                    if searchModel.deviceOptions.isEmpty {
                        Text("No source devices yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(searchModel.deviceOptions) { device in
                            Button {
                                searchModel.toggleSourceDevice(device.value)
                            } label: {
                                HStack {
                                    Text(device.title)
                                    Spacer()
                                    Text("\(device.count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if searchModel.selectedSourceDevices.contains(device.value) {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Clear") {
                        searchModel.clearAllFilters()
                    }
                }
            }
        }
    }
}

private extension ClipItemDateFilter {
    var label: String {
        switch self {
        case .any:
            return "Any Time"
        case .today:
            return "Today"
        case .yesterday:
            return "Yesterday"
        case .last7Days:
            return "Last 7 Days"
        case .last30Days:
            return "Last 30 Days"
        }
    }
}

private extension ItemType {
    var label: String {
        switch self {
        case .text:
            return "Text"
        case .richText:
            return "Rich Text"
        case .image:
            return "Image"
        case .file:
            return "File"
        case .url:
            return "Link"
        case .code:
            return "Code"
        case .color:
            return "Color"
        case .mixed:
            return "Mixed"
        }
    }
}

private extension ClipItemSourceDevice {
    var label: String {
        switch self {
        case .thisDevice:
            return "This Device"
        case .unknown:
            return "Unknown"
        case .named(let name):
            return name
        }
    }
}

private extension View {
    @ViewBuilder
    func glassButtonFallbackBackground(isHighlighted: Bool) -> some View {
        #if os(iOS)
        if #available(iOS 26, *) {
            self.glassEffect(
                isHighlighted ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                in: .circle
            )
        } else {
            self.background(
                Circle()
                    .fill(isHighlighted ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.18))
            )
        }
        #else
        self.background(
            Circle()
                .fill(isHighlighted ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.18))
        )
        #endif
    }
}
