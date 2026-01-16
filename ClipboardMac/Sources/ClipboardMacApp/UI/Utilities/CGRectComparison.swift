import CoreData
import CoreGraphics

// MARK: - CGRect Approximate Equality Utilities
// Shared utilities for comparing CGRect values with tolerance to handle floating-point precision issues.
// Using higher tolerance (5.0) by default to prevent layout jitter from triggering unnecessary updates.

/// Compares two dictionaries of CGRect values for approximate equality.
/// - Parameters:
///   - lhs: First dictionary mapping IDs to CGRect frames
///   - rhs: Second dictionary mapping IDs to CGRect frames
///   - tolerance: Maximum difference allowed for each component (default: 5.0)
/// - Returns: True if all corresponding rects are approximately equal
func framesApproximatelyEqual(
    _ lhs: [NSManagedObjectID: CGRect],
    _ rhs: [NSManagedObjectID: CGRect],
    tolerance: CGFloat = 5.0
) -> Bool {
    guard lhs.count == rhs.count else { return false }
    for (key, lhsRect) in lhs {
        guard let rhsRect = rhs[key] else { return false }
        if !rectsApproximatelyEqual(lhsRect, rhsRect, tolerance: tolerance) {
            return false
        }
    }
    return true
}

/// Compares two optional CGRect values for approximate equality.
/// - Parameters:
///   - lhs: First optional CGRect
///   - rhs: Second optional CGRect
///   - tolerance: Maximum difference allowed for each component (default: 5.0)
/// - Returns: True if both are nil, or both are non-nil and approximately equal
func rectsApproximatelyEqual(
    _ lhs: CGRect?,
    _ rhs: CGRect?,
    tolerance: CGFloat = 5.0
) -> Bool {
    guard let lhs = lhs, let rhs = rhs else { return lhs == nil && rhs == nil }
    return rectsApproximatelyEqual(lhs, rhs, tolerance: tolerance)
}

/// Compares two CGRect values for approximate equality.
/// - Parameters:
///   - lhs: First CGRect
///   - rhs: Second CGRect
///   - tolerance: Maximum difference allowed for each component (default: 5.0)
/// - Returns: True if all components are within tolerance
func rectsApproximatelyEqual(
    _ lhs: CGRect,
    _ rhs: CGRect,
    tolerance: CGFloat = 5.0
) -> Bool {
    abs(lhs.origin.x - rhs.origin.x) <= tolerance
        && abs(lhs.origin.y - rhs.origin.y) <= tolerance
        && abs(lhs.size.width - rhs.size.width) <= tolerance
        && abs(lhs.size.height - rhs.size.height) <= tolerance
}
