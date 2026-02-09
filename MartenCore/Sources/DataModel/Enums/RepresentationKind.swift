import Foundation

public enum RepresentationKind: Int16, CaseIterable, Sendable {
    case plainText = 0
    case rtf = 1
    case html = 2
    case markdown = 3
    case png = 10
    case jpeg = 11
    case tiff = 12
    case pdf = 20
    case fileURL = 30
    case url = 31
    case custom = 99
}
