import CoreData
import Foundation

@objc(Pinboard)
public class Pinboard: NSManagedObject {
}

public extension Pinboard {
    var itemCount: Int {
        return items?.count ?? 0
    }
}
