import Foundation

public enum ItemType: Int16, CaseIterable, Sendable {
    case text = 0
    case richText = 1
    case image = 2
    case file = 3
    case url = 4
    case code = 5
    case mixed = 99
}
