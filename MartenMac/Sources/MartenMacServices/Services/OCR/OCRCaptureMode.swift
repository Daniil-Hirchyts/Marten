import Foundation

public enum OCRCaptureMode: String, CaseIterable, Codable, Sendable {
    case staticSnapshot
    case liveScreen

    public var settingsTitle: String {
        switch self {
        case .staticSnapshot:
            return "Static Snapshot"
        case .liveScreen:
            return "Live Screen"
        }
    }
}
