import Foundation

public enum RetentionPolicy: String, CaseIterable {
    case day
    case week
    case month
    case year
    case forever

    public func retentionDate(reference: Date = Date()) -> Date? {
        let calendar = Calendar.current
        switch self {
        case .day:
            return calendar.date(byAdding: .day, value: -1, to: reference)
        case .week:
            return calendar.date(byAdding: .day, value: -7, to: reference)
        case .month:
            return calendar.date(byAdding: .day, value: -30, to: reference)
        case .year:
            return calendar.date(byAdding: .day, value: -365, to: reference)
        case .forever:
            return nil
        }
    }
}
