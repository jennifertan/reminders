import BackgroundTasks
import SwiftData
import UIKit
import UserNotifications

/// Which ring of a reminder an alert is for.
enum AlarmEvent: String {
    case preAlarm, main, autoSnooze, snooze
}

/// Queues local notifications for the next rings of every reminder.
///
/// iOS keeps at most 64 pending notifications per app, so Ringlet queues the soonest ones and tops the
/// queue up whenever the app opens, closes, changes a reminder, or gets a background refresh.
@MainActor
enum NotificationScheduler {
    nonisolated static let refreshTaskID = "au.com.ringlet.refresh"
    nonisolated static let categoryID = "RINGLET_REMINDER"
    nonisolated static let doneAction = "DONE"
    nonisolated static let snoozeAction = "SNOOZE"

    /// Critical alerts need an entitlement that Apple grants on request. Until it's granted, critical
    /// reminders are sent as Time Sensitive, which breaks through Focus but not the silent switch.
    /// Set this to true once the entitlement is added to Ringlet.entitlements.
    nonisolated static let hasCriticalAlertEntitlement = false

    private static let queuePrefix = "ring-"
    private static let snoozePrefix = "snooze-"
    private static let maxQueued = 60
    private static let daysAhead = 14

    static func registerCategories() {
        let done = UNNotificationAction(identifier: doneAction, title: "Mark Done", options: [])
        let snooze = UNNotificationAction(identifier: snoozeAction, title: "Snooze", options: [])
        let category = UNNotificationCategory(identifier: categoryID, actions: [done, snooze],
                                              intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func requestAuthorization() async -> Bool {
        var options: UNAuthorizationOptions = [.alert, .sound, .badge]
        if hasCriticalAlertEntitlement { options.insert(.criticalAlert) }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: options)) ?? false
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func isAuthorized() async -> Bool {
        let status = await authorizationStatus()
        return [.authorized, .provisional, .ephemeral].contains(status)
    }

    /// Reschedules from the app's own store. Safe to call from anywhere.
    static func rescheduleAll() async {
        await reschedule(context: Store.container.mainContext)
    }

    static func pendingCount() async -> Int {
        await UNUserNotificationCenter.current().pendingNotificationRequests().count
    }

    /// Replaces the queued notifications with the next rings of every reminder that's turned on.
    static func reschedule(context: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        let queued = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(queuePrefix) }
        center.removePendingNotificationRequests(withIdentifiers: queued)
        guard await isAuthorized() else { return }

        let reminders = (try? context.fetch(FetchDescriptor<Reminder>())) ?? []
        let marks = Planner.marksByKey((try? context.fetch(FetchDescriptor<OccurrenceMark>())) ?? [])
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let now = Date.now

        var rings: [(date: Date, occurrence: Occurrence, event: AlarmEvent, number: Int)] = []
        // Start far enough back that nags running on from an earlier day still ring.
        let nagDays = (reminders.map { $0.autoSnoozeMinutes * $0.autoSnoozeTimes }.max() ?? 0) / 1440 + 1
        // Look far enough ahead that a pre-alarm weeks before its ring still gets queued.
        let leadDays = (reminders.map(\.preAlarmMinutes).max() ?? 0) / 1440 + 1
        for offset in -nagDays..<(daysAhead + leadDays) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for occurrence in Planner.occurrences(on: day, reminders: reminders, marks: marks)
            where marks[occurrence.key]?.isDone != true && marks[occurrence.key]?.isSkipped != true {
                let reminder = occurrence.reminder
                if reminder.preAlarmMinutes > 0 {
                    rings.append((date: occurrence.date.addingTimeInterval(-Double(reminder.preAlarmMinutes) * 60),
                                  occurrence: occurrence, event: AlarmEvent.preAlarm, number: 0))
                }
                rings.append((date: occurrence.date, occurrence: occurrence, event: AlarmEvent.main, number: 0))
                if reminder.autoSnoozeMinutes > 0 {
                    for number in 1...max(1, reminder.autoSnoozeTimes) {
                        let date = occurrence.date.addingTimeInterval(Double(reminder.autoSnoozeMinutes * number) * 60)
                        rings.append((date: date, occurrence: occurrence, event: AlarmEvent.autoSnooze, number: number))
                    }
                }
            }
        }

        let soonest = rings.filter { $0.date > now }.sorted { $0.date < $1.date }.prefix(maxQueued)
        for ring in soonest {
            let content = content(for: ring.occurrence, event: ring.event)
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: ring.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let id = "\(queuePrefix)\(ring.occurrence.key)|\(ring.event.rawValue)\(ring.number)"
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
        scheduleRefresh()
    }

    static func content(for occurrence: Occurrence, event: AlarmEvent) -> UNMutableNotificationContent {
        let reminder = occurrence.reminder
        let time = occurrence.date.formatted(date: .omitted, time: .shortened)
        let content = UNMutableNotificationContent()
        content.title = reminder.message
        switch event {
        case .preAlarm:
            content.subtitle = "Coming up at \(time)"
        case .main:
            content.subtitle = reminder.kind == .wakeUp ? "Wake-up alarm, \(time)" : time
        case .autoSnooze, .snooze:
            content.subtitle = "Still to do, from \(time)"
        }
        content.body = reminder.notes
        content.sound = reminder.sound.notificationSound(critical: reminder.isCritical && event != .preAlarm,
                                                         volume: reminder.criticalVolume)
        if event != .preAlarm {
            content.categoryIdentifier = categoryID
        }
        if reminder.isCritical {
            content.interruptionLevel = hasCriticalAlertEntitlement ? .critical : .timeSensitive
        } else {
            content.interruptionLevel = .active
        }
        content.threadIdentifier = reminder.id.uuidString
        content.userInfo = [
            "key": occurrence.key,
            "event": event.rawValue,
            "date": occurrence.date.timeIntervalSince1970,
            "snoozeMinutes": reminder.snoozeMinutes,
        ]
        return content
    }

    /// Rings again after the reminder's snooze time.
    static func snooze(_ occurrence: Occurrence) async {
        let content = content(for: occurrence, event: .snooze)
        await snooze(content: content, key: occurrence.key, minutes: occurrence.reminder.snoozeMinutes)
    }

    static func snooze(content original: UNNotificationContent, key: String, minutes: Int) async {
        guard let content = original.mutableCopy() as? UNMutableNotificationContent else { return }
        content.userInfo["event"] = AlarmEvent.snooze.rawValue
        content.categoryIdentifier = categoryID
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(max(1, minutes)) * 60, repeats: false)
        let request = UNNotificationRequest(identifier: snoozePrefix + key, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Clears anything still waiting to ring for a ring that's been dealt with.
    static func clear(key: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [snoozePrefix + key])
        center.removeDeliveredNotifications(withIdentifiers: [snoozePrefix + key])
    }

    /// Asks iOS to wake Ringlet now and then so the queue never runs dry.
    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date.now.addingTimeInterval(6 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// Handles notification taps and the Mark Done and Snooze buttons, and shows the alarm screen
/// when a reminder rings while Ringlet is open.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in NotificationScheduler.registerCategories() }
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        let info = notification.request.content.userInfo
        let event = AlarmEvent(rawValue: info["event"] as? String ?? "") ?? .main
        guard event != .preAlarm, AlarmScreen.isOn, let key = info["key"] as? String else {
            return [.banner, .sound, .list]
        }
        await MainActor.run { AppRouter.shared.showAlarm(key: key, event: event) }
        // The alarm screen plays the sound itself.
        return [.list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        let info = content.userInfo
        guard let key = info["key"] as? String else { return }

        switch response.actionIdentifier {
        case NotificationScheduler.doneAction:
            await MainActor.run {
                let context = Store.container.mainContext
                OccurrenceMark.findOrInsert(key, in: context).isDone = true
                try? context.save()
                NotificationScheduler.clear(key: key)
            }
            await NotificationScheduler.rescheduleAll()
        case NotificationScheduler.snoozeAction:
            let minutes = info["snoozeMinutes"] as? Int ?? 10
            await NotificationScheduler.snooze(content: content, key: key, minutes: minutes)
        default:
            let time = info["date"] as? Double
            await MainActor.run {
                let router = AppRouter.shared
                router.tab = .days
                if let time {
                    router.day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: time))
                }
            }
        }
    }
}
