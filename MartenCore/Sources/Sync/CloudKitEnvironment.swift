import Foundation

/// Represents the CloudKit environment.
public enum CloudKitEnvironment: String, CaseIterable, Sendable {
    /// The production environment.
    case production
    
    /// The development environment.
    case development
}
