import Foundation

public struct TransientContentClassifier {
    public init() {}

    public func isTransient(types: [String], dataSize: Int) -> Bool {
        if dataSize < 10 {
            return true
        }

        let hasNonDynamicType = types.contains { type in
            !type.hasPrefix("dyn.") && !type.hasPrefix("_")
        }

        for type in types {
            if type == "com.apple.pasteboard.promised-file-url" {
                return true
            }
            if type == "com.apple.pasteboard.promised-file-content-type" {
                return true
            }
            if type.contains("promised-file-url") {
                return true
            }
            if type.contains("promised-file-content-type") {
                return true
            }
            if !hasNonDynamicType, type.hasPrefix("dyn.") {
                return true
            }
            if !hasNonDynamicType, type.hasPrefix("_") {
                return true
            }
        }

        return false
    }
}
