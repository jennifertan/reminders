import SwiftData
import SwiftUI

/// Every reminder, with search and an on/off switch for each.
struct ReminderListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Reminder.createdAt) private var reminders: [Reminder]
    @State private var search = ""
    @State private var selected: Reminder?
    @State private var readingNotes: Reminder?
    @State private var viewingImage: Reminder?
    @State private var editing: Reminder?
    @State private var deleting: Reminder?
    @State private var isAdding = false
    @State private var isShowingSettings = false

    var body: some View {
        List {
            if reminders.isEmpty {
                ContentUnavailableView {
                    Label("No Reminders Yet", systemImage: "bell")
                } description: {
                    Text("Tap + to add a one-time, repeating, wake-up or cycle reminder.")
                }
                .listRowBackground(Color.clear)
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(filtered) { reminder in
                    ReminderRow(reminder: reminder) { selected = reminder }
                }
            }
        }
        .ringletBackground()
        .searchable(text: $search, prompt: "Search messages and notes")
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { isShowingSettings = true } label: { Label("Settings", systemImage: "gearshape") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                AddButton { isAdding = true }
            }
        }
        .confirmationDialog(selected?.message ?? "", isPresented: isShowingActions, titleVisibility: .visible,
                            presenting: selected) { reminder in
            Button("View Message and Notes") { readingNotes = reminder }
            Button("View Image") { viewingImage = reminder }
            Button("Edit Reminder") { editing = reminder }
            Button("Test the Alarm") { testAlarm(reminder) }
            Button("Delete Reminder", role: .destructive) { deleting = reminder }
        } message: { reminder in
            Text(reminder.rule.summary)
        }
        .sheet(item: $readingNotes) { NotesView(reminder: $0) }
        .sheet(item: $viewingImage) { ImageView(reminder: $0) }
        .sheet(item: $editing) { ReminderFormView(reminder: $0) }
        .sheet(isPresented: $isAdding) { TypePickerView(startDay: .now) }
        .sheet(isPresented: $isShowingSettings) { SettingsView() }
        .deleteReminderAlert($deleting)
    }

    private var filtered: [Reminder] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let matching = query.isEmpty ? reminders : reminders.filter {
            $0.message.localizedCaseInsensitiveContains(query) || $0.notes.localizedCaseInsensitiveContains(query)
        }
        return matching.sorted { ($0.rule.minutes.first ?? 0) < ($1.rule.minutes.first ?? 0) }
    }

    private var isShowingActions: Binding<Bool> {
        Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })
    }

    /// Shows the alarm screen for today's next ring of this reminder, or a ring right now.
    private func testAlarm(_ reminder: Reminder) {
        let calendar = Calendar.current
        let minute = calendar.component(.hour, from: .now) * 60 + calendar.component(.minute, from: .now)
        let key = Planner.key(reminderID: reminder.id, day: .now, minute: minute)
        AppRouter.shared.showAlarm(key: key, event: .main)
    }
}

struct ReminderRow: View {
    @Bindable var reminder: Reminder
    let onOpen: () -> Void
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onOpen) {
                HStack(spacing: 14) {
                    ReminderImage(reminder)
                        .opacity(isDimmed ? 0.45 : 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reminder.message).font(.headline)
                        Text(reminder.rule.timesSummary).font(.subheadline).monospacedDigit()
                        Text(reminder.rule.summary + (reminder.isPast ? " · past" : ""))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(isDimmed ? Color.secondary : Color.primary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle(isOn: $reminder.isEnabled) {
                Text(reminder.isEnabled ? "On" : "Off")
            }
            .labelsHidden()
            .onChange(of: reminder.isEnabled) {
                try? modelContext.save()
                Task { await NotificationScheduler.reschedule(context: modelContext) }
            }
        }
        .padding(.vertical, 2)
    }

    private var isDimmed: Bool { !reminder.isEnabled || reminder.isPast }
}

#Preview {
    NavigationStack { ReminderListView() }
        .modelContainer(PreviewContainer.shared)
}
