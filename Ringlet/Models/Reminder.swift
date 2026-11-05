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
    /// Off hides it from the Calendar tab. It still rings and shows on the Days tab.
    var showsInCalendar = true
    /// The other app's id when this was imported, so importing again doesn't add duplicates.
    var importedID: String?

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

    var hasNotes: Bool { !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

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
    /// Skipped on purpose: not done, not missed, and it won't ring or nag.
    var isSkipped = false
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

    /// Marks a ring done or not. A one-time reminder has nothing left to do once it's done, so it
    /// turns off with it, and turns back on if it's unticked.
    static func setDone(_ isDone: Bool, key: String, in context: ModelContext) {
        let mark = findOrInsert(key, in: context)
        mark.isDone = isDone
        if isDone { mark.isSkipped = false }
        guard let id = Planner.parse(key)?.reminderID else { return }
        var descriptor = FetchDescriptor<Reminder>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let reminder = try? context.fetch(descriptor).first, reminder.kind == .oneTime {
            reminder.isEnabled = !isDone
        }
    }

    /// Clears a one-time reminder's done mark and turns it on, for when it's been given a new life:
    /// switched back on, or edited or moved to a new date.
    static func reopen(_ reminder: Reminder, in context: ModelContext) {
        guard reminder.kind == .oneTime, let minute = reminder.rule.minutes.first else { return }
        let key = Planner.key(reminderID: reminder.id, day: reminder.start, minute: minute)
        guard let mark = find(key, in: context), mark.isDone else { return }
        context.delete(mark)
        reminder.isEnabled = true
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

/// Reads the exports made from an Alarmed backup: done items for Done History, or active
/// reminders, which become Ringlet reminders.
enum AlarmedImport {
    enum Result {
        case history(added: Int)
        case reminders(added: Int)
    }

    private struct File: Decodable {
        let items: [Item]
    }

    private struct Item: Decodable {
        let id: String
        let title: String
        let notes: String?
        let dueDate: String?
        let completedDate: String?
        let repeatRule: Repeat?
        let leadTime: LeadTime?
        let nagMinutes: Int?

        enum CodingKeys: String, CodingKey {
            case id, title, notes, dueDate, completedDate, leadTime, nagMinutes
            case repeatRule = "repeat"
        }
    }

    private struct Repeat: Decodable {
        let frequency: String
        let interval: Int
        /// 1 is Sunday, as in Calendar.
        let daysOfWeekEK: [Int]?
        /// For monthly rules: 4 is the fourth, -1 the last.
        let setPositions: [Int]?
        let endDate: String?
    }

    private struct LeadTime: Decodable {
        let amount: Int
        let unit: String
    }

    /// Adds the file's items that aren't already in the store.
    static func run(data: Data, into context: ModelContext) throws -> Result {
        let file = try JSONDecoder().decode(File.self, from: data)
        let result: Result
        if file.items.contains(where: { $0.completedDate != nil }) {
            result = .history(added: importHistory(file.items, into: context))
        } else {
            result = .reminders(added: importReminders(file.items, into: context))
        }
        try context.save()
        return result
    }

    private static func importHistory(_ items: [Item], into context: ModelContext) -> Int {
        let existing = Set(((try? context.fetch(FetchDescriptor<ArchivedDone>())) ?? []).map(\.sourceID))
        let instant = ISO8601DateFormatter()
        var added = 0
        for item in items where !existing.contains(sourceID(item)) {
            guard let completed = item.completedDate.flatMap(instant.date(from:)) else { continue }
            context.insert(ArchivedDone(
                sourceID: sourceID(item),
                source: "Alarmed",
                title: item.title,
                notes: item.notes ?? "",
                completedAt: completed,
                dueAt: item.dueDate.flatMap(localDate),
                repeatSummary: item.repeatRule.map(summary) ?? ""
            ))
            added += 1
        }
        return added
    }

    private static func importReminders(_ items: [Item], into context: ModelContext) -> Int {
        let existing = Set(((try? context.fetch(FetchDescriptor<Reminder>())) ?? []).compactMap(\.importedID))
        let calendar = Calendar.current
        var added = 0
        for item in items where !existing.contains(sourceID(item)) {
            guard let due = item.dueDate.flatMap(localDate) else { continue }
            let kind: ReminderKind = switch item.repeatRule?.frequency {
            case "daily": .daily
            case "weekly": .weekly
            case "monthly": .monthly
            case "yearly": .yearly
            default: .oneTime
            }
            let reminder = Reminder(kind: kind)
            reminder.importedID = sourceID(item)
            reminder.message = item.title
            reminder.notes = item.notes ?? ""
            // The next ring anchors the schedule, so every-2-weeks and every-6-months rules stay in step.
            reminder.start = calendar.startOfDay(for: due)
            reminder.times = [calendar.component(.hour, from: due) * 60 + calendar.component(.minute, from: due)]
            if let rule = item.repeatRule {
                reminder.interval = max(1, rule.interval)
                let weekday = calendar.component(.weekday, from: due)
                reminder.weekdays = rule.daysOfWeekEK ?? [weekday]
                if kind == .monthly {
                    if let position = rule.setPositions?.first {
                        reminder.monthlyModeRaw = MonthlyMode.weekday.rawValue
                        reminder.nthWeek = position
                        reminder.nthWeekday = rule.daysOfWeekEK?.first ?? weekday
                    } else {
                        reminder.monthDays = [calendar.component(.day, from: due)]
                    }
                }
                if let end = rule.endDate.flatMap(localDate) {
                    reminder.endModeRaw = EndMode.endDate.rawValue
                    reminder.endDate = end
                }
            }
            if let lead = item.leadTime {
                reminder.preAlarmMinutes = lead.amount * (lead.unit == "days" ? 1440 : lead.unit == "hours" ? 60 : 1)
            }
            if let nag = item.nagMinutes, nag > 0 {
                reminder.autoSnoozeMinutes = nag
                reminder.autoSnoozeTimes = 5
            }
            context.insert(reminder)
            added += 1
        }
        return added
    }

    private static func sourceID(_ item: Item) -> String { "alarmed:" + item.id }

    /// Alarmed stores alarm times as wall-clock times with no zone.
    private static func localDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: text)
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

extension AlarmedImport {
    /// Loads the Alarmed records bundled with the app, once. Later builds without the files,
    /// or reminders deleted after loading, are left alone.
    static func loadBundledRecordsOnce(into context: ModelContext) {
        let key = "loadedAlarmedRecords"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        var loadedAny = false
        for name in ["alarmed-done-history", "alarmed-active"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  (try? run(data: data, into: context)) != nil
            else { continue }
            loadedAny = true
        }
        if loadedAny { UserDefaults.standard.set(true, forKey: key) }
    }
}

extension OccurrenceMark {
    /// Older builds left a done one-time reminder switched on. Turns those off.
    static func turnOffDoneOneTimeReminders(in context: ModelContext) {
        let marks = (try? context.fetch(FetchDescriptor<OccurrenceMark>(predicate: #Predicate { $0.isDone }))) ?? []
        let reminders = (try? context.fetch(FetchDescriptor<Reminder>(predicate: #Predicate { $0.isEnabled }))) ?? []
        let doneKeys = Set(marks.map(\.key))
        for reminder in reminders where reminder.kind == .oneTime {
            guard let minute = reminder.rule.minutes.first else { continue }
            if doneKeys.contains(Planner.key(reminderID: reminder.id, day: reminder.start, minute: minute)) {
                reminder.isEnabled = false
            }
        }
        try? context.save()
    }

    /// Older builds moved a one-time reminder's only ring with a mark, which left the reminder
    /// itself on the old date. Moves those reminders properly.
    static func applyMovedOneTimeReminders(in context: ModelContext) {
        let marks = (try? context.fetch(FetchDescriptor<OccurrenceMark>(predicate: #Predicate { $0.movedTo != nil }))) ?? []
        guard !marks.isEmpty else { return }
        let reminders = (try? context.fetch(FetchDescriptor<Reminder>())) ?? []
        let byID = Dictionary(reminders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let calendar = Calendar.current
        for mark in marks {
            guard let moved = mark.movedTo, let parsed = Planner.parse(mark.key),
                  let reminder = byID[parsed.reminderID], reminder.kind == .oneTime,
                  // Skips a mark left from when this reminder repeated.
                  calendar.isDate(parsed.date, inSameDayAs: reminder.start)
            else { continue }
            reminder.start = calendar.startOfDay(for: moved)
            reminder.times = [calendar.component(.hour, from: moved) * 60 + calendar.component(.minute, from: moved)]
            context.delete(mark)
        }
        try? context.save()
    }
}
