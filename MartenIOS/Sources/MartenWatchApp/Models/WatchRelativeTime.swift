import Foundation

enum WatchRelativeTime {
    static func short(from date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 {
            return "now"
        }

        let minutes = Int(interval / 60)
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = Int(interval / 3600)
        if hours < 24 {
            return "\(hours)h"
        }

        let days = Int(interval / 86400)
        if days < 30 {
            return "\(days)d"
        }

        let months = Int(interval / (86400 * 30))
        if months < 12 {
            return "\(months)mo"
        }

        let years = Int(interval / (86400 * 365))
        return "\(years)y"
    }
}
