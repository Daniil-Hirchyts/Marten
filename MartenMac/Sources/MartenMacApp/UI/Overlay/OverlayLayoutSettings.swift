import CoreGraphics
import Foundation

enum OverlayLayoutAxis: String {
    case horizontal
    case vertical
}

enum OverlayScreenEdge: String, CaseIterable, Identifiable {
    case bottom
    case top
    case left
    case right

    var id: String { rawValue }

    var layoutAxis: OverlayLayoutAxis {
        switch self {
        case .bottom, .top:
            return .horizontal
        case .left, .right:
            return .vertical
        }
    }

    var settingsTitle: String {
        switch self {
        case .bottom:
            return "Bottom"
        case .top:
            return "Top"
        case .left:
            return "Left"
        case .right:
            return "Right"
        }
    }
}

struct OverlayLayoutSettings {
    enum Keys {
        static let overlayScreenEdge = "overlayScreenEdge"
        static let overlayHeight = "OverlayHeight"
        static let overlayWidth = "OverlayWidth"
    }

    static let defaultEdge: OverlayScreenEdge = .bottom
    static let defaultHorizontalSize: CGFloat = 320
    static let defaultVerticalSize: CGFloat = 420

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var overlayScreenEdge: OverlayScreenEdge {
        get {
            guard
                let raw = userDefaults.string(forKey: Keys.overlayScreenEdge),
                let edge = OverlayScreenEdge(rawValue: raw)
            else {
                return Self.defaultEdge
            }
            return edge
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: Keys.overlayScreenEdge)
        }
    }

    var horizontalSize: CGFloat {
        let stored = userDefaults.double(forKey: Keys.overlayHeight)
        return stored > 0 ? CGFloat(stored) : Self.defaultHorizontalSize
    }

    var verticalSize: CGFloat {
        let stored = userDefaults.double(forKey: Keys.overlayWidth)
        return stored > 0 ? CGFloat(stored) : Self.defaultVerticalSize
    }

    func persistedSize(for axis: OverlayLayoutAxis) -> CGFloat {
        switch axis {
        case .horizontal:
            return horizontalSize
        case .vertical:
            return verticalSize
        }
    }

    func setPersistedSize(_ size: CGFloat, for axis: OverlayLayoutAxis) {
        switch axis {
        case .horizontal:
            userDefaults.set(size, forKey: Keys.overlayHeight)
        case .vertical:
            userDefaults.set(size, forKey: Keys.overlayWidth)
        }
    }
}
