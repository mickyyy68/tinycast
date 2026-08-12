import Foundation

/// Coarse date sections shared by recency-ordered palette lists.
enum DateBucket: Int {
    case today, yesterday, thisWeek, thisMonth, earlier

    var title: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek: return "This Week"
        case .thisMonth: return "This Month"
        case .earlier: return "Earlier"
        }
    }

    init(for date: Date, now: Date = Date(), calendar: Calendar = .current) {
        if calendar.isDateInToday(date) {
            self = .today
        } else if calendar.isDateInYesterday(date) {
            self = .yesterday
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            self = .thisWeek
        } else if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            self = .thisMonth
        } else {
            self = .earlier
        }
    }
}
