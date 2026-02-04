import Foundation

public protocol CrashReporting: Sendable {
    func setup()
    func recordError(_ error: Error, userInfo: [String: Any]?)
    func recordEvent(_ name: String, parameters: [String: Any]?)
    func setUserID(_ userID: String?)
}

