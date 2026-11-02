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
        _date = State(initialValue: occurrence.date)
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
                    Text("Moves only the \(original.formatted(date: .abbreviated, time: .shortened)) reminder.")
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
                        let mark = OccurrenceMark.findOrInsert(occurrence.key, in: modelContext)
                        mark.movedTo = date == original ? nil : date
                        mark.isDone = false
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

    private func finish() {
        try? modelContext.save()
        NotificationScheduler.clear(key: occurrence.key)
        Task { await NotificationScheduler.reschedule(context: modelContext) }
        dismiss()
    }
}

/// Every ring that was marked done, newest first, grouped by day.
struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var reminders: [Reminder]
    @Query(filter: #Predicate<OccurrenceMark> { $0.isDone }) private var marks: [OccurrenceMark]
    @State private var search = ""

    private struct Entry: Identifiable {
        let id: String
        let reminder: Reminder
        let date: Date
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
                    ForEach(days, id: \.self) { day in
                        Section(day.formatted(.dateTime.weekday(.wide).day().month(.wide).year())) {
                            ForEach(filtered.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }) { entry in
                                HStack(spacing: 14) {
                                    ReminderImage(entry.reminder)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.reminder.message).font(.headline)
                                        Text(entry.date, style: .time)
                                            .font(.subheadline)
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                                }
                                .padding(.vertical, 2)
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

    private var entries: [Entry] {
        let byID = Dictionary(reminders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return marks.compactMap { mark in
            guard let parsed = Planner.parse(mark.key), let reminder = byID[parsed.reminderID] else { return nil }
            return Entry(id: mark.key, reminder: reminder, date: mark.movedTo ?? parsed.date)
        }
        .sorted { $0.date > $1.date }
    }

    private var filtered: [Entry] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.reminder.message.localizedCaseInsensitiveContains(query)
                || $0.reminder.notes.localizedCaseInsensitiveContains(query)
        }
    }

    private var days: [Date] {
        var seen = Set<Date>()
        return filtered.map { Calendar.current.startOfDay(for: $0.date) }.filter { seen.insert($0).inserted }
    }
}
