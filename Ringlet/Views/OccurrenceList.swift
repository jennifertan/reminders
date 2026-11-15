import SwiftData
import SwiftUI

/// One reminder ring in a day's list, with its done / missed button.
struct OccurrenceRow: View {
    let occurrence: Occurrence
    let status: OccurrenceStatus
    let onOpen: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onOpen) {
                HStack(spacing: 14) {
                    ReminderImage(occurrence.reminder)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(occurrence.reminder.message)
                                .font(.headline)
                                .foregroundStyle(status == .done || status == .skipped ? Color.secondary : Color.primary)
                            if occurrence.reminder.hasNotes { NoteDot() }
                        }
                        HStack(spacing: 6) {
                            Text(occurrence.date, style: .time)
                                .monospacedDigit()
                            if status == .skipped {
                                Text("SKIPPED")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                            if occurrence.isMoved {
                                Text("MOVED")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color.highlight)
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            StatusButton(status: status, action: onToggle)
        }
        .padding(.vertical, 4)
    }
}

/// A tiny dot beside a reminder's name when it has a note.
struct NoteDot: View {
    var body: some View {
        Circle()
            .fill(Color.highlight)
            .frame(width: 7, height: 7)
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 3 }
            .accessibilityLabel("Has a note")
    }
}

/// The circle at the end of each row: empty, a green tick, a grey dash, or a red cross.
struct StatusButton: View {
    let status: OccurrenceStatus
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                switch status {
                case .done:
                    Circle().fill(Color.accentColor)
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                case .skipped:
                    Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 2.5)
                    Image(systemName: "minus").font(.system(size: 14, weight: .heavy)).foregroundStyle(.secondary)
                case .missed:
                    Circle().strokeBorder(Color.red, lineWidth: 2.5)
                    Image(systemName: "xmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(.red)
                case .upcoming:
                    Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 2.5)
                }
            }
            .frame(width: 32, height: 32)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: status == .done)
        .accessibilityLabel(label)
    }

    private var label: String {
        switch status {
        case .done: "Done. Double-tap to undo."
        case .skipped: "Skipped. Double-tap to undo."
        case .missed: "Missed. Double-tap to mark done."
        case .upcoming: "Mark done"
        }
    }
}

/// A day's reminders with everything you can do to them: mark done, reschedule, read notes,
/// see the picture, edit and delete.
struct OccurrenceList: View {
    let day: Date
    /// Owned by the screen, which shows them with occurrenceActions on its List.
    @Binding var actions: OccurrenceActions
    /// Kinds of reminder to leave out, for the Calendar's filter.
    var hiddenKinds: Set<ReminderKind> = []
    /// Leaves out reminders switched off for the Calendar.
    var isCalendar = false

    @Environment(\.modelContext) private var modelContext
    @Query private var reminders: [Reminder]
    @Query private var marks: [OccurrenceMark]
    @State private var now = Date.now

    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        let markMap = Planner.marksByKey(marks)
        let shown = reminders.filter { !hiddenKinds.contains($0.kind) && (!isCalendar || $0.showsInCalendar) }
        let occurrences = Planner.occurrences(on: day, reminders: shown, marks: markMap)

        Group {
            if occurrences.isEmpty {
                Section {
                    EmptyDay(day: day, hasReminders: !reminders.isEmpty, hiddenByFilter: hiddenCount(markMap))
                }
            } else {
                Section {
                    ForEach(occurrences) { occurrence in
                        OccurrenceRow(
                            occurrence: occurrence,
                            status: Planner.status(of: occurrence, marks: markMap, now: now),
                            onOpen: { actions.selected = occurrence },
                            onToggle: { toggleDone(occurrence) }
                        )
                    }
                } header: {
                    Tally(occurrences: occurrences, marks: markMap, now: now)
                }
            }
        }
        .onReceive(clock) { now = $0 }
    }

    /// Rings on this day that the Calendar's type filter leaves out.
    private func hiddenCount(_ markMap: [String: OccurrenceMark]) -> Int {
        guard isCalendar, !hiddenKinds.isEmpty else { return 0 }
        let hidden = reminders.filter { hiddenKinds.contains($0.kind) && $0.showsInCalendar }
        return Planner.occurrences(on: day, reminders: hidden, marks: markMap).count
    }

    private func toggleDone(_ occurrence: Occurrence) {
        let mark = OccurrenceMark.findOrInsert(occurrence.key, in: modelContext)
        // Tapping a skipped ring undoes the skip rather than marking it done.
        if mark.isSkipped {
            mark.isSkipped = false
        } else {
            OccurrenceMark.setDone(!mark.isDone, key: occurrence.key, in: modelContext)
        }
        if mark.isDone { NotificationScheduler.clear(key: occurrence.key) }
        try? modelContext.save()
        Task { await NotificationScheduler.reschedule(context: modelContext) }
    }
}

private struct Tally: View {
    let occurrences: [Occurrence]
    let marks: [String: OccurrenceMark]
    let now: Date

    var body: some View {
        let statuses = occurrences.map { Planner.status(of: $0, marks: marks, now: now) }
        HStack(spacing: 14) {
            dot(.accentColor, "\(statuses.filter { $0 == .done }.count) done")
            dot(.red, "\(statuses.filter { $0 == .missed }.count) missed")
            dot(.secondary, "\(statuses.filter { $0 == .upcoming }.count) to come")
            if statuses.contains(.skipped) {
                dot(.secondary, "\(statuses.filter { $0 == .skipped }.count) skipped")
            }
        }
        .font(.footnote)
        .textCase(nil)
    }

    private func dot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
    }
}

private struct EmptyDay: View {
    let day: Date
    let hasReminders: Bool
    var hiddenByFilter = 0
    @Environment(\.modelContext) private var modelContext
    @State private var isAdding = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(hasReminders ? "Nothing on this day" : "No reminders yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.heading)
            Text(hiddenByFilter > 0
                 ? "\(hiddenByFilter) reminder\(hiddenByFilter == 1 ? " is" : "s are") hidden by the Calendar filter."
                 : hasReminders
                 ? "Reminders show up on every day they're due."
                 : "Add a one-time, repeating, wake-up or cycle reminder, or load some examples to see how it works.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add a Reminder") { isAdding = true }
                .buttonStyle(.borderedProminent)
            if !hasReminders {
                Button("Load Examples") {
                    Reminder.makeSamples().forEach(modelContext.insert)
                    try? modelContext.save()
                    Task { await NotificationScheduler.reschedule(context: modelContext) }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .sheet(isPresented: $isAdding) { TypePickerView(startDay: day) }
    }
}

extension View {
    /// Asks before deleting a reminder, then removes it. Done History keeps what was done.
    func deleteReminderAlert(_ reminder: Binding<Reminder?>) -> some View {
        modifier(DeleteReminderAlert(reminder: reminder))
    }
}

private struct DeleteReminderAlert: ViewModifier {
    @Binding var reminder: Reminder?
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content.alert("Delete \u{201C}\(reminder?.message ?? "")\u{201D}?",
                      isPresented: Binding(get: { reminder != nil }, set: { if !$0 { reminder = nil } }),
                      presenting: reminder) { reminder in
            Button("Delete", role: .destructive) {
                OccurrenceMark.delete(reminder, keepingHistoryIn: modelContext)
                try? modelContext.save()
                Task { await NotificationScheduler.reschedule(context: modelContext) }
            }
            Button("Keep It", role: .cancel) {}
        } message: { _ in
            Text("This removes the reminder. You can't undo it. Anything you've marked done stays in Done History.")
        }
    }
}

/// What's open for a ring in an OccurrenceList: its action menu and the sheets it leads to.
struct OccurrenceActions {
    var selected: Occurrence?
    var rescheduling: Occurrence?
    var readingNotes: Reminder?
    var viewingImage: Reminder?
    var editing: Reminder?
    var deleting: Reminder?
}

extension View {
    /// Goes on the List itself, not on its contents. Inside a List these attach to the rows,
    /// which come and go as the list updates and take an open sheet with them.
    func occurrenceActions(_ actions: Binding<OccurrenceActions>) -> some View {
        modifier(OccurrenceActionsModifier(actions: actions))
    }
}

private struct OccurrenceActionsModifier: ViewModifier {
    @Binding var actions: OccurrenceActions
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content
            .confirmationDialog(actions.selected?.reminder.message ?? "", isPresented: isShowingActions,
                                titleVisibility: .visible, presenting: actions.selected) { occurrence in
                if occurrence.reminder.kind.repeats {
                    let isSkipped = OccurrenceMark.find(occurrence.key, in: modelContext)?.isSkipped == true
                    Button(isSkipped ? "Undo Skip" : "Skip") { setSkipped(!isSkipped, occurrence) }
                }
                Button("Reschedule") { afterDialog { actions.rescheduling = occurrence } }
                Button("View Message and Notes") { afterDialog { actions.readingNotes = occurrence.reminder } }
                Button("View Image") { afterDialog { actions.viewingImage = occurrence.reminder } }
                Button("Edit Reminder") { afterDialog { actions.editing = occurrence.reminder } }
                Button("Delete Reminder", role: .destructive) { afterDialog { actions.deleting = occurrence.reminder } }
            } message: { occurrence in
                Text("\(occurrence.date.formatted(date: .abbreviated, time: .shortened)) · \(occurrence.reminder.rule.summary)")
            }
            .sheet(item: $actions.rescheduling) { RescheduleView(occurrence: $0) }
            .sheet(item: $actions.readingNotes) { NotesView(reminder: $0) }
            .sheet(item: $actions.viewingImage) { ImageView(reminder: $0) }
            .sheet(item: $actions.editing) { ReminderFormView(reminder: $0, followsDay: true) }
            .deleteReminderAlert($actions.deleting)
    }

    private var isShowingActions: Binding<Bool> {
        Binding(get: { actions.selected != nil }, set: { if !$0 { actions.selected = nil } })
    }

    private func setSkipped(_ isSkipped: Bool, _ occurrence: Occurrence) {
        let mark = OccurrenceMark.findOrInsert(occurrence.key, in: modelContext)
        mark.isSkipped = isSkipped
        if isSkipped {
            mark.isDone = false
            NotificationScheduler.clear(key: occurrence.key)
        }
        try? modelContext.save()
        Task { await NotificationScheduler.reschedule(context: modelContext) }
    }
}

/// Runs a step that opens a sheet or alert once a confirmation dialog has finished closing. On iOS 27
/// one presented while the dialog is still animating away is dropped, so the first tap did nothing.
@MainActor
func afterDialog(_ action: @escaping @MainActor () -> Void) {
    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(350))
        action()
    }
}
