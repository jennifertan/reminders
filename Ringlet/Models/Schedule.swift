import Foundation

/// The kinds of reminder you can pick when adding one.
enum ReminderKind: String, CaseIterable, Identifiable, Codable {
    case oneTime, daily, weekly, monthly, yearly, wakeUp, cycle

    var id: Self { self }

    var title: String {
        switch self {
        case .oneTime: "One-Time"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        case .wakeUp: "Wake-Up Alarm"
        case .cycle: "Cycle"
        }
    }

    var examples: [String] {
        switch self {
        case .oneTime: ["May 13 at 11:00 AM", "Oct 23 at 9:30 AM"]
        case .daily: ["Every day, every 6 hours", "Every 3 days at 9:00 AM and 4:00 PM"]
        case .weekly: ["Fridays, every week", "Tue, Wed and Sat, every 2 weeks"]
        case .monthly: ["Days 1, 10 and 20, every month", "First Monday of every month"]
        case .yearly: ["Nov 13, every year", "May 19, every 2 years"]
        case .wakeUp: ["7:00 AM on weekdays", "9:00 AM on weekends"]
        case .cycle: ["21 days on, then 7 days off", "3 days on, then 2 days off"]
        }
    }

    var symbol: String {
        switch self {
        case .oneTime: "calendar.badge.clock"
        case .daily: "repeat"
        case .weekly: "calendar"
        case .monthly: "calendar.circle"
        case .yearly: "birthday.cake"
        case .wakeUp: "sun.max"
        case .cycle: "arrow.triangle.2.circlepath"
        }
    }

    /// The word used in "Every 2 weeks", or nil when the kind doesn't repeat that way.
    var intervalUnit: String? {
        switch self {
        case .daily: "day"
        case .weekly: "week"
        case .monthly: "month"
        case .yearly: "year"
        default: nil
        }
    }

    var repeats: Bool { self != .oneTime }

    /// Daily and cycle reminders can ring every few hours instead of at set times.
    var allowsHourlyTimes: Bool { self == .daily || self == .cycle }
}

enum TimeMode: String, Codable { case specific, everyHours }
enum MonthlyMode: String, Codable { case days, weekday }
enum EndMode: String, Codable { case endDate, totalDays }

/// The parts of a reminder that decide when it rings. Kept free of SwiftData so it is easy to test.
struct ScheduleRule: Equatable {
    var kind: ReminderKind
    /// Midnight on the first day the reminder can ring. For one-time and yearly reminders it is the date itself.
    var start: Date
    /// Minutes after midnight.
    var times: [Int]
    var timeMode: TimeMode = .specific
    var everyHours = 4
    var fromMinute = 8 * 60
    var toMinute = 20 * 60
    /// Every N days, weeks, months or years.
    var interval = 1
    /// Calendar weekdays: 1 is Sunday, 7 is Saturday.
    var weekdays: Set<Int> = []
    var monthlyMode: MonthlyMode = .days
    /// Days of the month. 0 means the last day of the month.
    var monthDays: Set<Int> = []
    /// 1 to 4, or -1 for the last one in the month.
    var nthWeek = 1
    var nthWeekday = 2
    var cycleOn = 21
    var cycleOff = 7
    var endMode: EndMode = .endDate
    /// nil means it never ends.
    var endDate: Date?
    var totalDays = 30

    static let lastDayOfMonth = 0

    /// Ring times for each day the reminder is due, in minutes after midnight, sorted.
    var minutes: [Int] {
        if kind.allowsHourlyTimes && timeMode == .everyHours {
            let step = max(1, everyHours) * 60
            guard toMinute >= fromMinute else { return [fromMinute] }
            return Array(stride(from: fromMinute, through: toMinute, by: step))
        }
        return Array(Set(times)).sorted()
    }

    /// Points the day pickers at the start date: the weekday for weekly, the day of the month and
    /// weekday for monthly. Used when they were never chosen for this kind, for example after a
    /// one-time reminder is changed to Weekly, so it repeats on its own day and not some other one.
    mutating func matchDays(calendar: Calendar = .current, weekdays matchWeekdays: Bool, month matchMonth: Bool) {
        let weekday = calendar.component(.weekday, from: start)
        if matchWeekdays { weekdays = [weekday] }
        if matchMonth {
            monthDays = [calendar.component(.day, from: start)]
            nthWeekday = weekday
            let day = calendar.component(.day, from: start)
            let lastDay = calendar.range(of: .day, in: .month, for: start)?.count ?? 31
            nthWeek = day + 7 > lastDay ? -1 : (day - 1) / 7 + 1
        }
    }

    func occurs(on day: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: day)
        let first = calendar.startOfDay(for: start)
        guard day >= first else { return false }
        let daysIn = calendar.dateComponents([.day], from: first, to: day).day ?? 0

        if kind.repeats {
            switch endMode {
            case .endDate:
                if let endDate, day > calendar.startOfDay(for: endDate) { return false }
            case .totalDays:
                if daysIn >= max(1, totalDays) { return false }
            }
        }

        let every = max(1, interval)
        let weekday = calendar.component(.weekday, from: day)

        switch kind {
        case .oneTime:
            return day == first

        case .daily:
            return daysIn % every == 0

        case .weekly:
            guard weekdays.contains(weekday) else { return false }
            // Counts whole weeks between the start's week and this day's week by plain day
            // arithmetic, so it doesn't depend on how Calendar works out week-of-year intervals.
            let startWeekday = calendar.component(.weekday, from: first)
            let startOffset = (startWeekday - calendar.firstWeekday + 7) % 7
            let weeks = (daysIn + startOffset) / 7
            return weeks % every == 0

        case .monthly:
            let a = calendar.dateComponents([.year, .month], from: first)
            let b = calendar.dateComponents([.year, .month, .day], from: day)
            let months = ((b.year ?? 0) - (a.year ?? 0)) * 12 + (b.month ?? 0) - (a.month ?? 0)
            guard months % every == 0 else { return false }
            let dayOfMonth = b.day ?? 1
            let lastDay = calendar.range(of: .day, in: .month, for: day)?.count ?? 31
            switch monthlyMode {
            case .days:
                return monthDays.contains(dayOfMonth)
                    || (monthDays.contains(Self.lastDayOfMonth) && dayOfMonth == lastDay)
            case .weekday:
                guard weekday == nthWeekday else { return false }
                if nthWeek == -1 { return dayOfMonth + 7 > lastDay }
                return (dayOfMonth - 1) / 7 + 1 == nthWeek
            }

        case .yearly:
            let a = calendar.dateComponents([.year, .month, .day], from: first)
            let b = calendar.dateComponents([.year, .month, .day], from: day)
            let years = (b.year ?? 0) - (a.year ?? 0)
            guard years % every == 0, a.month == b.month else { return false }
            // A reminder set for the 29th of February rings on the 28th in other years.
            let lastDay = calendar.range(of: .day, in: .month, for: day)?.count ?? 31
            return b.day == min(a.day ?? 1, lastDay)

        case .wakeUp:
            return weekdays.contains(weekday)

        case .cycle:
            let length = max(1, cycleOn) + max(0, cycleOff)
            return daysIn % length < max(1, cycleOn)
        }
    }
}

// MARK: - Describing a schedule in words

extension ScheduleRule {
    static func weekdayText(_ days: Set<Int>) -> String {
        if days == [2, 3, 4, 5, 6] { return "Mon to Fri" }
        if days == [1, 7] { return "Weekends" }
        if days.count == 7 { return "Every day" }
        // Monday first.
        let order = days.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }
        let names = Calendar.current.shortWeekdaySymbols
        return order.map { names[$0 - 1] }.joined(separator: ", ")
    }

    /// For example "Tue, 3 Nov", with the year added when it isn't this year.
    static func dateText(_ date: Date) -> String {
        let style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        let isThisYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        return date.formatted(isThisYear ? style : style.year())
    }

    static func timeText(_ minute: Int) -> String {
        let date = Calendar.current.date(byAdding: .minute, value: minute, to: Calendar.current.startOfDay(for: .now)) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// For example "Every 2 weeks on Mon to Fri" or "Monthly on days 15, last".
    var summary: String {
        let every = max(1, interval)
        switch kind {
        case .oneTime:
            return "One-Time"
        case .daily:
            return every > 1 ? "Every \(every) days" : "Daily"
        case .weekly:
            return (every > 1 ? "Every \(every) weeks" : "Weekly") + " on \(Self.weekdayText(weekdays))"
        case .monthly:
            let which: String
            switch monthlyMode {
            case .days:
                let sorted = monthDays.sorted { ($0 == 0 ? 99 : $0) < ($1 == 0 ? 99 : $1) }
                which = "days " + sorted.map { $0 == 0 ? "last" : String($0) }.joined(separator: ", ")
            case .weekday:
                let name = Calendar.current.weekdaySymbols[max(1, min(7, nthWeekday)) - 1]
                which = "the \(Self.ordinal(nthWeek).lowercased()) \(name)"
            }
            return (every > 1 ? "Every \(every) months" : "Monthly") + " on \(which)"
        case .yearly:
            return (every > 1 ? "Every \(every) years" : "Yearly") + " on \(start.formatted(.dateTime.month(.abbreviated).day()))"
        case .wakeUp:
            return "Wake-Up Alarm, \(Self.weekdayText(weekdays))"
        case .cycle:
            return "Cycle, \(cycleOn) days on, \(cycleOff) off"
        }
    }

    /// For example "8:00 AM, 2:00 PM" or "Every 3 hours, 9:00 AM to 6:00 PM".
    var timesSummary: String {
        if kind.allowsHourlyTimes && timeMode == .everyHours {
            return "Every \(everyHours) h, \(Self.timeText(fromMinute)) to \(Self.timeText(toMinute))"
        }
        let list = minutes.map(Self.timeText).joined(separator: ", ")
        if kind == .oneTime {
            return "\(Self.dateText(start)), \(list)"
        }
        return list
    }

    static func ordinal(_ n: Int) -> String {
        switch n {
        case -1: "Last"
        case 1: "First"
        case 2: "Second"
        case 3: "Third"
        case 4: "Fourth"
        default: "Fifth"
        }
    }
}
