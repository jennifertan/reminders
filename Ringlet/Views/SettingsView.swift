import SwiftData
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system
    @Query private var reminders: [Reminder]
    @State private var status = UNAuthorizationStatus.notDetermined
    @State private var queued = 0
    @State private var isConfirmingDeleteAll = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    switch status {
                    case .denied:
                        Label("Notifications are off", systemImage: "bell.slash.fill").foregroundStyle(.red)
                        Button("Turn On in Settings") {
                            openURL(URL(string: UIApplication.openNotificationSettingsURLString)!)
                        }
                    case .notDetermined:
                        Button("Allow Notifications") {
                            Task {
                                _ = await NotificationScheduler.requestAuthorization()
                                await refresh()
                            }
                        }
                    default:
                        Label("Notifications are on", systemImage: "bell.badge.fill")
                        LabeledContent("Rings queued", value: "\(queued)")
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Ringlet queues the next 60 rings with iOS, which is the most it allows, and tops the queue up each time you open the app. Open Ringlet at least every few days so nothing is missed.")
                }

                Section("Sounds") {
                    ForEach(ReminderSound.allCases.filter { $0 != .silent }) { sound in
                        Button {
                            SoundPlayer.shared.play(sound, repeating: false)
                        } label: {
                            Label(sound.title, systemImage: "play.circle")
                        }
                    }
                }

                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section {
                    Button("Load Example Reminders") {
                        Reminder.makeSamples().forEach(modelContext.insert)
                        save()
                    }
                    Button("Delete All Reminders", role: .destructive) { isConfirmingDeleteAll = true }
                        .disabled(reminders.isEmpty)
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Examples include medication, water, a wake-up alarm and a monthly bill so you can see every kind of schedule.")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                }
            }
            .ringletBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Delete all \(reminders.count) reminders?", isPresented: $isConfirmingDeleteAll,
                                titleVisibility: .visible) {
                Button("Delete All", role: .destructive) {
                    try? modelContext.delete(model: OccurrenceMark.self)
                    try? modelContext.delete(model: Reminder.self)
                    save()
                }
            } message: {
                Text("This removes every reminder and its history. You can't undo it.")
            }
            .task { await refresh() }
            .onDisappear { SoundPlayer.shared.stop() }
        }
    }

    private func refresh() async {
        status = await NotificationScheduler.authorizationStatus()
        queued = await NotificationScheduler.pendingCount()
    }

    private func save() {
        try? modelContext.save()
        Task {
            await NotificationScheduler.reschedule(context: modelContext)
            await refresh()
        }
    }
}

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("The circle on each reminder") {
                    row(.done, "Done. Tap the circle to mark a reminder done, and tap again to undo.")
                    row(.missed, "Missed. It's more than 30 minutes past and wasn't marked done.")
                    row(.upcoming, "Still to come, or just due.")
                    row(.skipped, "Skipped. You chose not to do this one, so it won't ring or count as missed.")
                }
                Section("Getting around") {
                    Text("Tap a reminder's name to reschedule just that one, read its notes, see its picture, edit it or delete it.")
                    Text("Use the arrows, or swipe left and right, to move between days.")
                    Text("The Calendar tab puts a dot on each day with reminders, red if something was missed.")
                    Text("In the Reminders tab, the switch turns a reminder off without deleting it.")
                }
                Section("When it rings") {
                    Text("Use Mark Done or Snooze right on the notification. If Ringlet is open, a full-screen alarm appears and keeps ringing until you choose.")
                    Text("Nag Me rings again at the interval you choose until you mark it done. A pre-alarm gives you a heads-up beforehand.")
                }
            }
            .ringletBackground()
            .navigationTitle("How Ringlet Works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func row(_ status: OccurrenceStatus, _ text: String) -> some View {
        HStack(spacing: 12) {
            StatusButton(status: status) {}
                .allowsHitTesting(false)
            Text(text)
        }
    }
}
