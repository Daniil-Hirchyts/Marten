import CoreData
import Foundation

@objc(StackSession)
public class StackSession: NSManagedObject {
}

public extension StackSession {
    var modeValue: StackMode {
        get { StackMode(rawValue: mode) ?? .sequential }
        set { mode = newValue.rawValue }
    }
}
