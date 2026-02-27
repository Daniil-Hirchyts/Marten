import MartenCore
import Foundation

@MainActor
final class OverlaySearchViewModel: ObservableObject {
    @Published var searchText: String = "" {
        didSet {
            if isSearchTextActive {
                searchResults = []
            }
            scheduleSearch()
        }
    }

    @Published var dateFilter: SearchDateFilter = .any
    @Published var typeFilters: Set<ItemType> = []
    @Published var appFilters: Set<String> = []

    @Published var selectedPinboardID: UUID? {
        didSet {
            guard oldValue != selectedPinboardID else { return }
            if isSearchTextActive {
                scheduleSearch(immediate: true)
            }
        }
    }

    @Published private(set) var searchResults: [ClipItem] = []
    @Published private(set) var appOptions: [AppFilterOption] = []

    private let store: ClipItemStore
    private var searchTask: Task<Void, Never>?
    private var searchGeneration: Int = 0
    private let debounceNanoseconds: UInt64
    private var lastAppOptionsSignature: Int?

    init(store: ClipItemStore, debounceNanoseconds: UInt64 = 250_000_000) {
        self.store = store
        self.debounceNanoseconds = debounceNanoseconds
        self.selectedPinboardID = nil
    }

    @MainActor
    convenience init(
        services: any CaptureServicesProviding, debounceNanoseconds: UInt64 = 250_000_000
    ) {
        self.init(store: services.clipItemStore, debounceNanoseconds: debounceNanoseconds)
    }

    var isSearchTextActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasActiveFilters: Bool {
        dateFilter != .any || !typeFilters.isEmpty || !appFilters.isEmpty
    }

    var isSearchActive: Bool {
        isSearchTextActive || hasActiveFilters
    }

    func clearFilters() {
        dateFilter = .any
        typeFilters.removeAll()
        appFilters.removeAll()
    }

    func refreshSearchNow() {
        scheduleSearch(immediate: true)
    }

    func applyFilters(to items: [ClipItem]) -> [ClipItem] {
        guard hasActiveFilters else { return items }
        let normalizedTypeFilters = Set(typeFilters.map { $0 == .richText ? .text : $0 })
        return items.filter { item in
            if !matchesDateFilter(item) {
                return false
            }
            if !normalizedTypeFilters.isEmpty, !normalizedTypeFilters.contains(item.itemTypeValue) {
                return false
            }
            if !appFilters.isEmpty {
                guard let key = appFilterKey(for: item) else { return false }
                if !appFilters.contains(key) {
                    return false
                }
            }
            return true
        }
    }

    func updateAppOptions(from allItems: [ClipItem]) {
        let selectedPinboardID = self.selectedPinboardID

        var hasher = Hasher()
        hasher.combine(selectedPinboardID)
        var count = 0
        var options: [String: AppFilterOption] = [:]

        for item in allItems {
            if let selectedPinboardID {
                guard item.pinboards?.contains(where: { $0.id == selectedPinboardID }) ?? false
                else {
                    continue
                }
            }
            guard let identity = sourceAppFilterIdentity(for: item) else { continue }
            hasher.combine(identity.id)
            hasher.combine(identity.name)
            hasher.combine(identity.bundleID)
            count += 1

            if options[identity.id] == nil {
                options[identity.id] = AppFilterOption(
                    id: identity.id,
                    name: identity.name,
                    bundleID: identity.bundleID
                )
            }
        }
        hasher.combine(count)
        let signature = hasher.finalize()

        if let lastAppOptionsSignature, lastAppOptionsSignature == signature {
            return
        }
        lastAppOptionsSignature = signature

        appOptions =
            options
            .map(\.value)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func scheduleSearch(immediate: Bool = false) {
        searchTask?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        searchTask = Task { [weak self] in
            guard let self else { return }
            if !immediate {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
            }
            await self.performSearch(generation: generation)
        }
    }

    private func performSearch(generation: Int) async {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }

        let pinboardID = selectedPinboardID
        let result: [ClipItem]
        do {
            result = try store.searchItems(query: trimmed, limit: 100, pinboardID: pinboardID)
        } catch {
            result = []
        }
        guard generation == searchGeneration else { return }
        searchResults = result
    }

    private func matchesDateFilter(_ item: ClipItem) -> Bool {
        switch dateFilter {
        case .any:
            return true
        case .today:
            return Calendar.current.isDateInToday(item.createdAt)
        case .last7Days:
            return item.createdAt >= dateCutoff(days: 7)
        case .last30Days:
            return item.createdAt >= dateCutoff(days: 30)
        }
    }

    private func dateCutoff(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date.distantPast
    }

    private func appFilterKey(for item: ClipItem) -> String? {
        sourceAppFilterIdentity(for: item)?.id
    }

    private func sourceAppFilterIdentity(for item: ClipItem) -> (id: String, name: String, bundleID: String?)? {
        let trimmedName = item.sourceAppName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasName = trimmedName?.isEmpty == false
        let resolvedBundle = SourceAppIdentity.resolvedBundleID(
            bundleID: item.sourceAppBundleID,
            appName: item.sourceAppName
        )

        if SourceAppIdentity.isMartenSource(bundleID: item.sourceAppBundleID, appName: item.sourceAppName) {
            return (
                id: SourceAppIdentity.martenBundleID,
                name: SourceAppIdentity.martenDisplayName,
                bundleID: SourceAppIdentity.martenBundleID
            )
        }

        if let resolvedBundle {
            return (
                id: resolvedBundle,
                name: hasName ? (trimmedName ?? resolvedBundle) : resolvedBundle,
                bundleID: resolvedBundle
            )
        }

        if let trimmedName, !trimmedName.isEmpty {
            return (
                id: trimmedName,
                name: trimmedName,
                bundleID: nil
            )
        }

        return nil
    }
}
