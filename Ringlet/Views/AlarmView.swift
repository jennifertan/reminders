import SwiftData
import SwiftUI

/// Full-screen alarm shown when a reminder rings while Ringlet is open. The sound repeats until you act.
struct AlarmView: View {
    let alarm: RingingAlarm

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var reminders: [Reminder]
    @Query private var marks: [OccurrenceMark]
    @State private var pulse = false

    var body: some View {
        let occurrence = Planner.occurrence(forKey: alarm.key, reminders: reminders, marks: Planner.marksByKey(marks))

        ZStack {
            Color(red: 0.07, green: 0.2, blue: 0.18).ignoresSafeArea()
            if let occurrence {
                content(occurrence)
            } else {
                Button("Close") { dismiss() }.buttonStyle(.borderedProminent)
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            pulse = true
            if let reminder = occurrence?.reminder {
                SoundPlayer.shared.play(reminder.sound, repeating: true,
                                        volume: reminder.isCritical ? reminder.criticalVolume : 1)
            }
        }
        .onDisappear { SoundPlayer.shared.stop() }
    }

    private func content(_ occurrence: Occurrence) -> some View {
        let reminder = occurrence.reminder
        return VStack(spacing: 18) {
            Spacer()
            ReminderImage(reminder, size: 128)
                .background {
                    RoundedRectangle(cornerRadius: 44, style: .continuous)
                        .stroke(Color.highlight, lineWidth: 2)
                        .padding(-14)
                        .scaleEffect(pulse ? 1.12 : 0.92)
                        .opacity(pulse ? 0 : 0.8)
                        .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulse)
                }
            Text(kicker(reminder))
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.highlight)
            Text(occurrence.date, style: .time)
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(reminder.message)
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            if !reminder.notes.isEmpty {
                Text(reminder.notes)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            VStack(spacing: 12) {
                Button {
                    OccurrenceMark.findOrInsert(occurrence.key, in: modelContext).isDone = true
                    NotificationScheduler.clear(key: occurrence.key)
                    finish()
                } label: {
                    Text("Mark Done").frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.highlight)
                .foregroundStyle(.black)

                Button {
                    Task { await NotificationScheduler.snooze(occurrence) }
                    finish()
                } label: {
                    Text("Snooze \(reminder.snoozeMinutes) min").frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.bordered)
                .tint(.white)

                Button("Dismiss") { finish() }
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 4)
            }
            .font(.headline)
        }
        .padding(28)
    }

    private func kicker(_ reminder: Reminder) -> String {
        switch alarm.event {
        case .preAlarm: "Coming up"
        case .snooze, .autoSnooze: "Still to do"
        case .main: reminder.kind == .wakeUp ? "Wake-up alarm" : "Reminder"
        }
    }

    private func finish() {
        SoundPlayer.shared.stop()
        try? modelContext.save()
        Task { await NotificationScheduler.reschedule(context: modelContext) }
        AppRouter.shared.alarm = nil
    }
}
