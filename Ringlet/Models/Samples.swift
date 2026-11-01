import Foundation
import SwiftData

/// Example reminders you can load from Settings or the empty Days screen to try Ringlet out.
extension Reminder {
    @MainActor
    static func makeSamples() -> [Reminder] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }
        func make(_ kind: ReminderKind, _ message: String, symbol: String, hue: Double,
                  times: [Int], start: Int = -30, configure: (Reminder) -> Void = { _ in }) -> Reminder {
            let reminder = Reminder(kind: kind)
            reminder.message = message
            reminder.symbol = symbol
            reminder.hue = hue
            reminder.times = times
            reminder.start = day(start)
            configure(reminder)
            return reminder
        }

        return [
            make(.wakeUp, "Wake up", symbol: "sun.max.fill", hue: 0.12, times: [6 * 60 + 45]),
            make(.daily, "Take medication", symbol: "pills.fill", hue: 0.97, times: [8 * 60, 14 * 60, 20 * 60]) {
                $0.notes = "1 tablet with food.\nRefill when the bottle is under 10."
                $0.autoSnoozeMinutes = 10
                $0.autoSnoozeTimes = 3
                $0.isCritical = true
                $0.criticalVolume = 0.7
            },
            make(.daily, "Drink water", symbol: "drop.fill", hue: 0.56, times: [9 * 60]) {
                $0.timeModeRaw = TimeMode.everyHours.rawValue
                $0.everyHours = 3
                $0.fromMinute = 9 * 60
                $0.toMinute = 18 * 60
                $0.soundRaw = ReminderSound.bells.rawValue
            },
            make(.daily, "Feed the dog", symbol: "pawprint.fill", hue: 0.08, times: [7 * 60 + 30, 18 * 60]) {
                $0.soundRaw = ReminderSound.marimba.rawValue
            },
            make(.weekly, "Team stand-up", symbol: "briefcase.fill", hue: 0.62, times: [9 * 60 + 30]) {
                $0.weekdays = [2, 4, 6]
                $0.preAlarmMinutes = 10
                $0.notes = "Room 4B or the usual video link."
            },
            make(.oneTime, "Call Mom", symbol: "phone.fill", hue: 0.72, times: [10 * 60], start: 2) {
                $0.notes = "Ask about the holiday plans."
            },
            make(.oneTime, "Dentist check-up", symbol: "cross.case.fill", hue: 0.0, times: [15 * 60], start: 6) {
                $0.preAlarmMinutes = 60
                $0.notes = "Bring insurance card."
            },
            make(.monthly, "Pay bills", symbol: "dollarsign.circle.fill", hue: 0.38, times: [12 * 60], start: -60) {
                $0.monthDays = [15, ScheduleRule.lastDayOfMonth]
            },
            make(.yearly, "Sam's birthday", symbol: "birthday.cake.fill", hue: 0.9, times: [9 * 60], start: 11) {
                $0.preAlarmMinutes = 24 * 60
            },
            make(.cycle, "Gym session", symbol: "dumbbell.fill", hue: 0.03, times: [18 * 60 + 30], start: -20) {
                $0.cycleOn = 3
                $0.cycleOff = 1
            },
            make(.monthly, "Water the plants", symbol: "leaf.fill", hue: 0.3, times: [10 * 60], start: -60) {
                $0.monthlyModeRaw = MonthlyMode.weekday.rawValue
                $0.nthWeek = 1
                $0.nthWeekday = 7
            },
        ]
    }
}

@MainActor
enum PreviewContainer {
    static let shared: ModelContainer = {
        let container = try! ModelContainer(
            for: Reminder.self, OccurrenceMark.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        Reminder.makeSamples().forEach { container.mainContext.insert($0) }
        return container
    }()
}
