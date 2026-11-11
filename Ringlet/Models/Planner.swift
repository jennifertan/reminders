import Foundation

/// One ring of a reminder on a particular day.
struct Occurrence: Identifiable, Hashable {
    let reminder: Reminder
    /// Identifies this ring on its original day and time, even after it's moved.
    let key: String
    /// When it rings, after any reschedule.
    let date: Date
    let isMoved: Bool

    var id: String { key }

    static func == (lhs: Occurrence, rhs: Occurrence) -> Bool { lhs.key == rhs.key && lhs.date == rhs.date }
    func hash(into hasher: inout Hasher) { hasher.combine(key) }
}

enum OccurrenceStatus { case done, skipped, missed, upcoming }

/// Works out which reminders ring on a day, and whether each ring was done or missed.
enum Planner {
    /// A ring counts as missed this long after its time.
    static let missedAfter: TimeInterval = 30 * 60

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func key(reminderID: UUID, day: Date, minute: Int) -> String {
        dayFormatter.timeZone = .current
        return "\(reminderID.uuidString)|\(dayFormatter.string(from: day))|\(minute)"
    }

    /// The reminder ID and original time stored in a key.
    static func parse(_ key: String) -> (reminderID: UUID, date: Date)? {
        let parts = key.split(separator: "|")
        guard parts.count == 3, let id = UUID(uuidString: String(parts[0])), let minute = Int(parts[2]) else { return nil }
        dayFormatter.timeZone = .current
        guard let day = dayFormatter.date(from: String(parts[1])) else { return nil }
        let date = Calendar.current.date(byAdding: .minute, value: minute, to: day) ?? day
        return (id, date)
    }

    static func marksByKey(_ marks: [OccurrenceMark]) -> [String: OccurrenceMark] {
        Dictionary(marks.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Every ring on a day, sorted by time. Rings moved away are left out and rings moved here are added.
    static func occurrences(on day: Date, reminders: [Reminder], marks: [String: OccurrenceMark],
                            includeTurnedOff: Bool = false) -> [Occurrence] {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: day)
        var result: [Occurrence] = []

        for reminder in reminders {
            let rule = reminder.rule
            guard rule.occurs(on: day, calendar: calendar) else { continue }
            for minute in rule.minutes {
                let ringKey = Self.key(reminderID: reminder.id, day: day, minute: minute)
                // A done one-time reminder is turned off, but stays on its day, ticked, so it can be undone.
                let isDoneOneTime = reminder.kind == .oneTime && marks[ringKey]?.isDone == true
                guard reminder.isEnabled || includeTurnedOff || isDoneOneTime else { continue }
                if marks[ringKey]?.movedTo != nil { continue }
                let date = calendar.date(byAdding: .minute, value: minute, to: day) ?? day
                result.append(Occurrence(reminder: reminder, key: ringKey, date: date, isMoved: false))
            }
        }

        let byID = Dictionary(reminders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for mark in marks.values {
            guard let moved = mark.movedTo, calendar.isDate(moved, inSameDayAs: day),
                  let parsed = parse(mark.key), let reminder = byID[parsed.reminderID],
                  reminder.isEnabled || includeTurnedOff
            else { continue }
            result.append(Occurrence(reminder: reminder, key: mark.key, date: moved, isMoved: true))
        }

        return withoutDuplicates(result, marks: marks)
            .sorted { ($0.date, $0.reminder.message) < ($1.date, $1.reminder.message) }
    }

    /// A ring moved onto the same minute as another ring of its reminder would show twice and ring
    /// twice, for example a weekly ring moved on a week. Keeps one, preferring a ring already done.
    private static func withoutDuplicates(_ rings: [Occurrence], marks: [String: OccurrenceMark]) -> [Occurrence] {
        var kept: [String: Occurrence] = [:]
        for ring in rings {
            let slot = "\(ring.reminder.id)|\(ring.date.timeIntervalSince1970)"
            guard let other = kept[slot] else {
                kept[slot] = ring
                continue
            }
            let isDone = marks[ring.key]?.isDone == true
            let otherIsDone = marks[other.key]?.isDone == true
            if isDone != otherIsDone ? isDone : other.isMoved {
                kept[slot] = ring
            }
        }
        return Array(kept.values)
    }

    /// Finds a ring from its key, wherever it has been moved to.
    static func occurrence(forKey key: String, reminders: [Reminder], marks: [String: OccurrenceMark]) -> Occurrence? {
        guard let parsed = parse(key), let reminder = reminders.first(where: { $0.id == parsed.reminderID }) else { return nil }
        if let moved = marks[key]?.movedTo {
            return Occurrence(reminder: reminder, key: key, date: moved, isMoved: true)
        }
        return Occurrence(reminder: reminder, key: key, date: parsed.date, isMoved: false)
    }

    static func status(of occurrence: Occurrence, marks: [String: OccurrenceMark], now: Date = .now) -> OccurrenceStatus {
        if marks[occurrence.key]?.isDone == true { return .done }
        if marks[occurrence.key]?.isSkipped == true { return .skipped }
        return occurrence.date.addingTimeInterval(missedAfter) < now ? .missed : .upcoming
    }
}
