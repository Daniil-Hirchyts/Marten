import CoreData
import SwiftUI

// MARK: - Preference Key

struct CardFramePreferenceKey: PreferenceKey {
    static let defaultValue: [NSManagedObjectID: CGRect] = [:]

    static func reduce(value: inout [NSManagedObjectID: CGRect], nextValue: () -> [NSManagedObjectID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Sweep Selection State

@MainActor
@Observable
final class SweepSelectionState {
    var isActive = false
    var addsToSelection = true
    var sweptObjectIDs: Set<NSManagedObjectID> = []
    private(set) var cardFrames: [NSManagedObjectID: CGRect] = [:]

    func updateFrames(_ frames: [NSManagedObjectID: CGRect]) {
        cardFrames = frames
    }

    func objectID(at point: CGPoint) -> NSManagedObjectID? {
        cardFrames.first(where: { $0.value.contains(point) })?.key
    }
}

// MARK: - View Extension

extension View {
    func reportCardFrame(objectID: NSManagedObjectID, coordinateSpace: String) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: CardFramePreferenceKey.self,
                        value: [objectID: proxy.frame(in: .named(coordinateSpace))]
                    )
            }
        )
    }
}
