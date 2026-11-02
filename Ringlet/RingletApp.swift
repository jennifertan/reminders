import SwiftData
import SwiftUI

/// The app's one store, shared with the notification delegate so Mark Done works from the lock screen.
@MainActor
enum Store {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: Reminder.self, OccurrenceMark.self, ArchivedDone.self)
        } catch {
            fatalError("Couldn't open the reminder store: \(error)")
        }
    }()
}

@main
@MainActor
struct RingletApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        // Launch with -seedSamples to start an empty store with the example reminders.
        let context = Store.container.mainContext
        if CommandLine.arguments.contains("-seedSamples"),
           (try? context.fetchCount(FetchDescriptor<Reminder>())) == 0 {
            Reminder.makeSamples().forEach(context.insert)
        }
        #endif
        Theme.applyBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(Store.container)
        .onChange(of: scenePhase) {
            // Top up the notification queue whenever the app opens or leaves the screen.
            guard scenePhase != .inactive else { return }
            let taskID = UIApplication.shared.beginBackgroundTask()
            Task {
                await NotificationScheduler.rescheduleAll()
                UIApplication.shared.endBackgroundTask(taskID)
            }
        }
        .backgroundTask(.appRefresh(NotificationScheduler.refreshTaskID)) {
            await NotificationScheduler.rescheduleAll()
        }
    }
}
