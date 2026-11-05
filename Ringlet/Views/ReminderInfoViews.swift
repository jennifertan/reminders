import SwiftData
import SwiftUI
import UIKit

/// The reminder's message and notes in full.
struct NotesView: View {
    let reminder: Reminder
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Message") {
                    Text(reminder.message).font(.title3.weight(.semibold))
                }
                Section("Notes") {
                    if reminder.notes.isEmpty {
                        Text("No notes. Add some with Edit Reminder.").foregroundStyle(.secondary)
                    } else {
                        Text(reminder.notes).textSelection(.enabled)
                    }
                }
                Section("Schedule") {
                    LabeledContent("Repeats", value: reminder.rule.summary)
                    LabeledContent("Times", value: reminder.rule.timesSummary)
                }
            }
            .ringletBackground()
            .navigationTitle("Message and Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The reminder's picture, large.
struct ImageView: View {
    let reminder: Reminder
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let data = reminder.photo, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    ReminderImage(reminder, size: 220)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.canvas)
            .navigationTitle(reminder.message)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

/// Moves one ring to another day or time. The rest of the schedule stays the same.
struct RescheduleView: View {
    let occurrence: Occurrence
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var date: Date

    init(occurrence: Occurrence) {
        self.occurrence = occurrence
        // A ring that has already gone starts from now, since it can only move forward.
        _date = State(initialValue: max(occurrence.date, .now))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("New time", selection: $date)
                    HStack {
                        quick("+10 min", minutes: 10)
                        quick("+1 hour", minutes: 60)
                        quick("Tomorrow", minutes: 24 * 60)
                    }
                    .buttonStyle(.bordered)
                } footer: {
                    if occurrence.reminder.kind == .oneTime {
                        Text("Moves this reminder to the new date and time.")
                    } else {
                        Text("Moves only the \(original.formatted(date: .abbreviated, time: .shortened)) reminder. The rest of the schedule stays the same.")
                    }
                }
                if occurrence.isMoved {
                    Section {
                        Button("Put Back to Original Time") {
                            OccurrenceMark.find(occurrence.key, in: modelContext)?.movedTo = nil
                            finish()
                        }
                    }
                }
            }
            .ringletBackground()
            .navigationTitle("Reschedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        if occurrence.reminder.kind == .oneTime {
                            moveOneTimeReminder()
                        } else {
                            let mark = OccurrenceMark.findOrInsert(occurrence.key, in: modelContext)
                            mark.movedTo = date == original ? nil : date
                            mark.isDone = false
                            mark.isSkipped = false
                        }
                        finish()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var original: Date { Planner.parse(occurrence.key)?.date ?? occurrence.date }

    private func quick(_ title: String, minutes: Int) -> some View {
        Button(title) { date = date.addingTimeInterval(Double(minutes) * 60) }
            .font(.footnote)
    }

    /// A one-time reminder has only this ring, so move the reminder itself. That way the
    /// Reminders tab and Calendar show the new date too.
    private func moveOneTimeReminder() {
        let calendar = Calendar.current
        let reminder = occurrence.reminder
        OccurrenceMark.reopen(reminder, in: modelContext)
        reminder.start = calendar.startOfDay(for: date)
        reminder.times = [calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)]
        if let mark = OccurrenceMark.find(occurrence.key, in: modelContext) {
            modelContext.delete(mark)
        }
    }

    private func finish() {
        try? modelContext.save()
        NotificationScheduler.clear(key: occurrence.key)
        Task { await NotificationScheduler.reschedule(context: modelContext) }
        dismiss()
    }
}

/// Every ring that was marked done, newest first, grouped by day, plus done items brought over from Alarmed.
struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var reminders: [Reminder]
    @Query(filter: #Predicate<OccurrenceMark> { $0.isDone }) private var marks: [OccurrenceMark]
    @Query private var archived: [ArchivedDone]
    @State private var search = ""

    private struct Entry: Identifiable {
        let id: String
        let title: String
        let notes: String
        let date: Date
        let detail: String
        let reminder: Reminder?
    }

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing Done Yet", systemImage: "checkmark.circle")
                    } description: {
                        Text("Reminders you mark as done show up here.")
                    }
                    .listRowBackground(Color.clear)
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(byDay, id: \.day) { group in
                        Section(group.day.formatted(.dateTime.weekday(.wide).day().month(.wide).year())) {
                            ForEach(group.entries) { entry in
                                row(entry)
                            }
                        }
                    }
                }
            }
            .ringletBackground()
            .searchable(text: $search, prompt: "Search done reminders")
            .navigationTitle("Done History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func row(_ entry: Entry) -> some View {
        HStack(spacing: 14) {
            if let reminder = entry.reminder {
                ReminderImage(reminder)
            } else {
                Image(systemName: "checkmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.secondary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.headline)
                Text(entry.date, style: .time)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if !entry.detail.isEmpty {
                    Text(entry.detail).font(.footnote).foregroundStyle(.secondary)
                }
                if !entry.notes.isEmpty {
                    Text(entry.notes).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, 2)
    }

    private static let hiddenKinds: Set<ReminderKind> = [.daily, .weekly]

    private var entries: [Entry] {
        let byID = Dictionary(reminders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let fromMarks: [Entry] = marks.compactMap { mark in
            guard let parsed = Planner.parse(mark.key), let reminder = byID[parsed.reminderID],
                  !Self.hiddenKinds.contains(reminder.kind)
            else { return nil }
            return Entry(id: mark.key, title: reminder.message, notes: "", date: mark.movedTo ?? parsed.date,
                         detail: reminder.rule.summary, reminder: reminder)
        }
        // Daily and weekly items like "Take tablets" would crowd out everything else.
        let fromArchive = archived.filter { item in
            !["day", "days", "week", "weeks"].contains { item.repeatSummary.hasSuffix(" " + $0) }
        }.map { item in
            Entry(id: item.sourceID, title: item.title, notes: item.notes, date: item.completedAt,
                  detail: ([item.source] + (item.repeatSummary.isEmpty ? [] : [item.repeatSummary])).joined(separator: " · "),
                  reminder: nil)
        }
        return (fromMarks + fromArchive).sorted { $0.date > $1.date }
    }

    private var filtered: [Entry] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.notes.localizedCaseInsensitiveContains(query)
        }
    }

    /// Newest day first; entries are already newest first.
    private var byDay: [(day: Date, entries: [Entry])] {
        Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }
            .map { ($0.key, $0.value) }
    }
}
