import CoreData
import Foundation
import MartenCore
import Observation

struct DashboardSourceAppOption: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleID: String?
    let count: Int
}

struct DashboardSourceDeviceOption: Identifiable, Hashable {
    let id: String
    let title: String
    let value: ClipItemSourceDevice
    let count: Int
}

@MainActor
@Observable
final class DashboardSearchModel {
    var query = "" {
        didSet {
            guard oldValue != query else { return }
            scheduleSearch()
        }
    }

    var dateFilter: ClipItemDateFilter = .any {
        didSet {
            guard oldValue != dateFilter else { return }
            scheduleSearch(immediate: true)
        }
    }

    var selectedTypes: Set<ItemType> = [] {
        didSet {
            guard oldValue != selectedTypes else { return }
            scheduleSearch(immediate: true)
        }
    }

    var selectedSourceApps: Set<String> = [] {
        didSet {
            guard oldValue != selectedSourceApps else { return }
            scheduleSearch(immediate: true)
        }
    }

    var selectedSourceDevices: Set<ClipItemSourceDevice> = [] {
        didSet {
            guard oldValue != selectedSourceDevices else { return }
            scheduleSearch(immediate: true)
        }
    }

    var selectedPinboardID: UUID? {
        didSet {
            guard oldValue != selectedPinboardID else { return }
            scheduleSearch(immediate: true)
        }
    }

    private(set) var results: [ClipItem] = []
    private(set) var quickResults: [ClipItem] = []
    private(set) var appOptions: [DashboardSourceAppOption] = []
    private(set) var deviceOptions: [DashboardSourceDeviceOption] = []
    private(set) var suggestedApps: [DashboardSourceAppOption] = []
    private(set) var isSearching = false

    private(set) var isVoiceRecording = false
    var voiceErrorMessage: String?

    private let queryService: any ClipItemQuerying
    private let voiceService: VoiceDictationService
    private let siriDonor: SiriSuggestionsDonor
    private let debounceNanoseconds: UInt64
    private var searchGeneration = 0
    private var searchTask: Task<Void, Never>?

    init(
        queryService: any ClipItemQuerying,
        voiceService: VoiceDictationService? = nil,
        siriDonor: SiriSuggestionsDonor? = nil,
        debounceNanoseconds: UInt64 = 250_000_000
    ) {
        self.queryService = queryService
        self.voiceService = voiceService ?? VoiceDictationService()
        self.siriDonor = siriDonor ?? SiriSuggestionsDonor()
        self.debounceNanoseconds = debounceNanoseconds
    }

    var hasActiveFilters: Bool {
        dateFilter != .any
            || !selectedTypes.isEmpty
            || !selectedSourceApps.isEmpty
            || !selectedSourceDevices.isEmpty
    }

    var isSearchTextActive: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isSearchActive: Bool {
        isSearchTextActive || hasActiveFilters
    }

    func clearSearchText() {
        query = ""
    }

    func clearAllFilters() {
        dateFilter = .any
        selectedTypes.removeAll()
        selectedSourceApps.removeAll()
        selectedSourceDevices.removeAll()
    }

    func toggleType(_ type: ItemType) {
        if selectedTypes.contains(type) {
            selectedTypes.remove(type)
        } else {
            selectedTypes.insert(type)
        }
    }

    func toggleSourceApp(_ appID: String) {
        if selectedSourceApps.contains(appID) {
            selectedSourceApps.remove(appID)
        } else {
            selectedSourceApps.insert(appID)
        }
    }

    func toggleSourceDevice(_ device: ClipItemSourceDevice) {
        if selectedSourceDevices.contains(device) {
            selectedSourceDevices.remove(device)
        } else {
            selectedSourceDevices.insert(device)
        }
    }

    func toggleVoiceDictation() {
        Task { [weak self] in
            guard let self else { return }
            do {
                if self.voiceService.isRecording {
                    self.voiceService.stop()
                    self.isVoiceRecording = false
                    return
                }

                try await self.voiceService.start { [weak self] transcript, isFinal in
                    self?.query = transcript
                    self?.isVoiceRecording = !(isFinal)
                }
                self.isVoiceRecording = self.voiceService.isRecording
                self.voiceErrorMessage = nil
            } catch {
                self.isVoiceRecording = false
                self.voiceErrorMessage = error.localizedDescription
            }
        }
    }

    func stopVoiceDictation() {
        voiceService.stop()
        isVoiceRecording = false
    }

    func donateOpenItem(_ item: ClipItem) {
        siriDonor.donateOpenItem(item)
    }

    func donateOpenPinboard(_ pinboard: Pinboard) {
        siriDonor.donateOpenPinboard(pinboard)
    }

    private var lastOptionsItemCount = 0
    private var lastOptionsFirstID: NSManagedObjectID?
    private var lastOptionsLastID: NSManagedObjectID?

    func updateOptions(from items: [ClipItem]) {
        let firstID = items.first?.objectID
        let lastID = items.last?.objectID
        if items.count == lastOptionsItemCount,
            firstID == lastOptionsFirstID,
            lastID == lastOptionsLastID
        {
            return
        }
        lastOptionsItemCount = items.count
        lastOptionsFirstID = firstID
        lastOptionsLastID = lastID

        var appCountByID: [String: Int] = [:]
        var appNameByID: [String: String] = [:]
        var appBundleByID: [String: String?] = [:]

        var deviceCountByValue: [ClipItemSourceDevice: Int] = [:]

        for item in items {
            if let appID = sourceAppID(for: item) {
                appCountByID[appID, default: 0] += 1
                appNameByID[appID] = sourceAppName(for: item, fallback: appID)
                appBundleByID[appID] = item.sourceAppBundleID
            }

            let deviceValue = sourceDeviceValue(for: item)
            deviceCountByValue[deviceValue, default: 0] += 1
        }

        appOptions = appCountByID
            .map { id, count in
                DashboardSourceAppOption(
                    id: id,
                    name: appNameByID[id] ?? id,
                    bundleID: appBundleByID[id] ?? nil,
                    count: count
                )
            }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.count > rhs.count
            }

        suggestedApps = Array(appOptions.prefix(5))

        deviceOptions = deviceCountByValue
            .map { value, count in
                DashboardSourceDeviceOption(
                    id: sourceDeviceID(for: value),
                    title: sourceDeviceTitle(for: value),
                    value: value,
                    count: count
                )
            }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.count > rhs.count
            }
    }

    private func scheduleSearch(immediate: Bool = false) {
        searchTask?.cancel()

        guard isSearchActive else {
            results = []
            quickResults = []
            isSearching = false
            return
        }

        searchGeneration += 1
        let generation = searchGeneration
        let request = ClipItemSearchRequest(
            query: query,
            pinboardID: selectedPinboardID,
            dateFilter: dateFilter,
            itemTypes: selectedTypes,
            sourceApps: selectedSourceApps,
            sourceDevices: selectedSourceDevices,
            limit: 150
        )
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        isSearching = true

        searchTask = Task { [weak self] in
            guard let self else { return }
            if !immediate {
                try? await Task.sleep(nanoseconds: self.debounceNanoseconds)
            }

            do {
                let items = try await self.queryService.search(request: request)
                guard !Task.isCancelled else { return }
                guard generation == self.searchGeneration else { return }

                self.results = items
                self.quickResults = Array(items.prefix(6))
                self.isSearching = false

                if !trimmedQuery.isEmpty {
                    self.siriDonor.donateSearch(query: trimmedQuery)
                }
            } catch {
                guard !Task.isCancelled else { return }
                guard generation == self.searchGeneration else { return }

                self.results = []
                self.quickResults = []
                self.isSearching = false
            }
        }
    }

    private func sourceAppID(for item: ClipItem) -> String? {
        if let bundleID = item.sourceAppBundleID?.trimmingCharacters(in: .whitespacesAndNewlines),
            !bundleID.isEmpty
        {
            return bundleID
        }

        if let sourceAppName = item.sourceAppName?.trimmingCharacters(in: .whitespacesAndNewlines),
            !sourceAppName.isEmpty
        {
            return sourceAppName
        }

        return nil
    }

    private func sourceAppName(for item: ClipItem, fallback: String) -> String {
        if let sourceAppName = item.sourceAppName?.trimmingCharacters(in: .whitespacesAndNewlines),
            !sourceAppName.isEmpty
        {
            return sourceAppName
        }
        return fallback
    }

    private func sourceDeviceValue(for item: ClipItem) -> ClipItemSourceDevice {
        let rawValue = item.lastModifiedBy?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawValue.isEmpty else {
            return .thisDevice
        }

        if isThisDeviceMarker(rawValue) {
            return .thisDevice
        }

        if isUnknownMarker(rawValue) {
            return .unknown
        }

        return .named(rawValue)
    }

    private func sourceDeviceID(for value: ClipItemSourceDevice) -> String {
        switch value {
        case .thisDevice:
            return "this-device"
        case .unknown:
            return "unknown-device"
        case .named(let name):
            return "named-\(name)"
        }
    }

    private func sourceDeviceTitle(for value: ClipItemSourceDevice) -> String {
        switch value {
        case .thisDevice:
            return "This Device"
        case .unknown:
            return "Unknown"
        case .named(let name):
            return name
        }
    }

    private func isThisDeviceMarker(_ rawValue: String) -> Bool {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "this device", "local", "local device", "current device":
            return true
        default:
            return false
        }
    }

    private func isUnknownMarker(_ rawValue: String) -> Bool {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "unknown", "n/a", "na":
            return true
        default:
            return false
        }
    }
}
