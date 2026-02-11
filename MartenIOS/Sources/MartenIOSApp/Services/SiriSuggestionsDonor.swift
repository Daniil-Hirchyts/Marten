import Foundation
import MartenCore

protocol UserActivityDonating {
    func donate(_ activity: NSUserActivity)
}

struct SystemUserActivityDonor: UserActivityDonating {
    func donate(_ activity: NSUserActivity) {
        #if os(iOS) || os(watchOS)
        activity.isEligibleForPrediction = true
        #endif
        activity.isEligibleForSearch = true
        activity.becomeCurrent()
    }
}

@MainActor
final class SiriSuggestionsDonor {
    static let searchActivityType = "com.hirchyts.marten.search"
    static let openItemActivityType = "com.hirchyts.marten.openItem"
    static let openPinboardActivityType = "com.hirchyts.marten.openPinboard"

    private let donor: any UserActivityDonating

    init(donor: (any UserActivityDonating)? = nil) {
        self.donor = donor ?? SystemUserActivityDonor()
    }

    func donateSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let activity = NSUserActivity(activityType: Self.searchActivityType)
        activity.title = "Search in Marten"
        activity.userInfo = ["query": trimmed]
        activity.keywords = [trimmed]
        donor.donate(activity)
    }

    func donateOpenItem(_ item: ClipItem) {
        let activity = NSUserActivity(activityType: Self.openItemActivityType)
        activity.title = "Open Marten Item"
        activity.userInfo = [
            "itemID": item.id.uuidString
        ]
        activity.persistentIdentifier = NSUserActivityPersistentIdentifier(item.id.uuidString)
        donor.donate(activity)
    }

    func donateOpenPinboard(_ pinboard: Pinboard) {
        let activity = NSUserActivity(activityType: Self.openPinboardActivityType)
        activity.title = "Open Pinboard"
        activity.userInfo = [
            "pinboardID": pinboard.id.uuidString
        ]
        activity.persistentIdentifier = NSUserActivityPersistentIdentifier(pinboard.id.uuidString)
        donor.donate(activity)
    }
}
