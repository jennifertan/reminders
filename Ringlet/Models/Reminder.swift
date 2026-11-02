import Foundation
import SwiftData

/// One reminder and everything about how and when it rings.
@Model
final class Reminder {
    var id = UUID()
    var createdAt = Date.now
    var kindRaw = ReminderKind.daily.rawValue
    var message = ""
    var notes = ""
    var soundRaw = ReminderSound.chime.rawValue
    /// An SF Symbol shown on a colored tile, used when there's no photo.
    var symbol = "bell.fill"
    /// Hue of the symbol tile, 0 to 1.
    var hue = 0.45
    @Attribute(.externalStorage) var photo: Data?
    var isEnabled = true

    // When it rings
    var start = Calendar.current.startOfDay(for: .now)
    var times: [Int] = [9 * 60]
    var timeModeRaw = TimeMode.specific.rawValue
    var everyHours = 4
    var fromMinute = 8 * 60
    var toMinute = 20 * 60
    var interval = 1
    var weekdays: [Int] = []
    var monthlyModeRaw = MonthlyMode.days.rawValue
    var monthDays: [Int] = []
    var nthWeek = 1
    var nthWeekday = 2
    var cycleOn = 21
    var cycleOff = 7
    var endModeRaw = EndMode.endDate.rawValue
    var endDate: Date?
    var totalDays = 30

    // Alerts
    /// Minutes before each time to give a heads-up. 0 is off.
    var preAlarmMinutes = 0
    /// Rings again this many minutes later if it isn't marked done. 0 is off.
    var autoSnoozeMinutes = 0
    var autoSnoozeTimes = 3
    var snoozeMinutes = 10
    var isCritical = false
    /// 0 to 1.
    var criticalVolume = 0.8

    init(kind: ReminderKind) {
        kindRaw = kind.rawValue
        let today = Calendar.current.startOfDay(for: .now)
        start = today
        weekdays = kind == .wakeUp ? [2, 3, 4, 5, 6] : [Calendar.current.component(.weekday, from: today)]
        monthDays = [Calendar.current.component(.day, from: today)]
        times = [kind == .wakeUp ? 7 * 60 : 9 * 60]
        if kind == .wakeUp {
            message = "Wake up"
            symbol = "sun.max.fill"
            hue = 0.12
            soundRaw = ReminderSound.rise.rawValue
            autoSnoozeMinutes = 9
            snoozeMinutes = 9
        }
    }

    var kind: ReminderKind {
        get { ReminderKind(rawValue: kindRaw) ?? .daily }
        set { kindRaw = newValue.rawValue }
    }

    var sound: ReminderSound {
        get { ReminderSound(rawValue: soundRaw) ?? .chime }
        set { soundRaw = newValue.rawValue }
    }

    var rule: ScheduleRule {
        get {
            ScheduleRule(
                kind: kind, start: start, times: times,
                timeMode: TimeMode(rawValue: timeModeRaw) ?? .specific,
                everyHours: everyHours, fromMinute: fromMinute, toMinute: toMinute,
                interval: interval, weekdays: Set(weekdays),
                monthlyMode: MonthlyMode(rawValue: monthlyModeRaw) ?? .days,
                monthDays: Set(monthDays), nthWeek: nthWeek, nthWeekday: nthWeekday,
                cycleOn: cycleOn, cycleOff: cycleOff,
                endMode: EndMode(rawValue: endModeRaw) ?? .endDate,
                endDate: endDate, totalDays: totalDays
            )
        }
        set {
            kind = newValue.kind
            start = Calendar.current.startOfDay(for: newValue.start)
            times = newValue.times.sorted()
            timeModeRaw = newValue.timeMode.rawValue
            everyHours = newValue.everyHours
            fromMinute = newValue.fromMinute
            toMinute = newValue.toMinute
            interval = newValue.interval
            weekdays = newValue.weekdays.sorted()
            monthlyModeRaw = newValue.monthlyMode.rawValue
            monthDays = newValue.monthDays.sorted()
            nthWeek = newValue.nthWeek
            nthWeekday = newValue.nthWeekday
            cycleOn = newValue.cycleOn
            cycleOff = newValue.cycleOff
            endModeRaw = newValue.endMode.rawValue
            endDate = newValue.endDate
            totalDays = newValue.totalDays
        }
    }

    /// True for a one-time reminder whose day has passed.
    var isPast: Bool {
        kind == .oneTime && start < Calendar.current.startOfDay(for: .now)
    }
}

/// What happened to one ring of a reminder: marked done, or moved to another time.
@Model
final class OccurrenceMark {
    @Attribute(.unique) var key: String
    var isDone = false
    var movedTo: Date?

    init(key: String) {
        self.key = key
    }

    static func find(_ key: String, in context: ModelContext) -> OccurrenceMark? {
        var descriptor = FetchDescriptor<OccurrenceMark>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func findOrInsert(_ key: String, in context: ModelContext) -> OccurrenceMark {
        if let mark = find(key, in: context) { return mark }
        let mark = OccurrenceMark(key: key)
        context.insert(mark)
        return mark
    }

    /// Removes marks for a reminder that has been deleted.
    static func deleteAll(for reminderID: UUID, in context: ModelContext) {
        let prefix = reminderID.uuidString + "|"
        let marks = (try? context.fetch(FetchDescriptor<OccurrenceMark>())) ?? []
        for mark in marks where mark.key.hasPrefix(prefix) {
            context.delete(mark)
        }
    }
}

/// A done item brought in from another app, kept for the Done History screen only.
@Model
final class ArchivedDone {
    /// The other app's id, so importing the same file twice doesn't add duplicates.
    @Attribute(.unique) var sourceID: String
    var source: String
    var title: String
    var notes: String
    var completedAt: Date
    var dueAt: Date?
    /// For example "Every 2 weeks", or empty for a one-off.
    var repeatSummary: String

    init(sourceID: String, source: String, title: String, notes: String, completedAt: Date, dueAt: Date?, repeatSummary: String) {
        self.sourceID = sourceID
        self.source = source
        self.title = title
        self.notes = notes
        self.completedAt = completedAt
        self.dueAt = dueAt
        self.repeatSummary = repeatSummary
    }
}

/// Reads the done-items export made from an Alarmed backup.
enum AlarmedImport {
    private struct File: Decodable {
        let items: [Item]
    }

    private struct Item: Decodable {
        let id: String
        let title: String
        let notes: String?
        let dueDate: String?
        let completedDate: String
        let repeatRule: Repeat?

        enum CodingKeys: String, CodingKey {
            case id, title, notes, dueDate, completedDate
            case repeatRule = "repeat"
        }
    }

    private struct Repeat: Decodable {
        let frequency: String
        let interval: Int
    }

    /// Adds the file's items that aren't already in the store, and returns how many were added.
    @discardableResult
    static func run(data: Data, into context: ModelContext) throws -> Int {
        let file = try JSONDecoder().decode(File.self, from: data)
        let existing = Set(((try? context.fetch(FetchDescriptor<ArchivedDone>())) ?? []).map(\.sourceID))
        let instant = ISO8601DateFormatter()
        // Alarmed stores alarm times as wall-clock times with no zone.
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = .current
        local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        var added = 0
        for item in file.items where !existing.contains("alarmed:" + item.id) {
            guard let completed = instant.date(from: item.completedDate) else { continue }
            context.insert(ArchivedDone(
                sourceID: "alarmed:" + item.id,
                source: "Alarmed",
                title: item.title,
                notes: item.notes ?? "",
                completedAt: completed,
                dueAt: item.dueDate.flatMap(local.date(from:)),
                repeatSummary: item.repeatRule.map(summary) ?? ""
            ))
            added += 1
        }
        try context.save()
        return added
    }

    private static func summary(_ rule: Repeat) -> String {
        let unit = switch rule.frequency {
        case "daily": "day"
        case "weekly": "week"
        case "monthly": "month"
        case "yearly": "year"
        default: rule.frequency
        }
        return rule.interval == 1 ? "Every \(unit)" : "Every \(rule.interval) \(unit)s"
    }
}
