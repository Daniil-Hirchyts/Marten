import Foundation

/// Controls who can access a shared pinboard.
public enum ShareAccessControl: Int16, Sendable {
    case onlyInvited = 0
    case anyoneWithLink = 1
}

/// Permission level for shared pinboard participants.
public enum SharePermission: Int16, Sendable {
    case owner = 0
    case canMakeChanges = 1
    case viewOnly = 2
}

/// Role of the current user in a shared pinboard.
public enum ShareRole: Int16, Sendable {
    case owner = 0
    case canMakeChanges = 1
    case viewOnly = 2
    case unknown = 3
}
