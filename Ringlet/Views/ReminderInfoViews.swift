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
