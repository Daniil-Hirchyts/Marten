import CoreData
import Foundation

@objc(ClipRepresentation)
public class ClipRepresentation: NSManagedObject {
}

public extension ClipRepresentation {
    var kindValue: RepresentationKind {
        get { RepresentationKind(rawValue: kind) ?? .plainText }
        set { kind = newValue.rawValue }
    }
}
