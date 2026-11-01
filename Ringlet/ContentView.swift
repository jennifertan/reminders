import SwiftData
import SwiftUI

enum AppTab { case days, reminders, calendar }

/// A reminder that is ringing on screen right now.
struct RingingAlarm: Identifiable, Equatable {
    let id = UUID()
    let key: String
    let event: AlarmEvent
}

/// App-wide navigation state, shared so a tapped notification can open the right day.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()
    var tab = AppTab.days
    var day = Calendar.current.startOfDay(for: .now)
    var alarm: RingingAlarm?

    func showAlarm(key: String, event: AlarmEvent) {
        // Don't stack the same ring twice, for example a snooze arriving while it's still showing.
        guard alarm?.key != key else { return }
        alarm = RingingAlarm(key: key, event: event)
    }
}

struct ContentView: View {
    @Bindable private var router = AppRouter.shared
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system

    var body: some View {
        TabView(selection: $router.tab) {
            NavigationStack {
                DaysView()
            }
            .tabItem { Label("Days", systemImage: "list.bullet.rectangle") }
            .tag(AppTab.days)

            NavigationStack {
                ReminderListView()
            }
            .tabItem { Label("Reminders", systemImage: "bell") }
            .tag(AppTab.reminders)

            NavigationStack {
                CalendarView()
            }
            .tabItem { Label("Calendar", systemImage: "calendar") }
            .tag(AppTab.calendar)
        }
        .fullScreenCover(item: $router.alarm) { alarm in
            AlarmView(alarm: alarm)
        }
        .tint(Color("AccentColor"))
        .onAppear { appearance.apply() }
        .onChange(of: appearance) { appearance.apply() }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewContainer.shared)
}
