import PhotosUI
import SwiftData
import SwiftUI

/// Everything you can set on a reminder, kept apart from the stored reminder until you tap Save.
struct ReminderDraft {
    var rule: ScheduleRule
    var message: String
    var notes: String
    var sound: ReminderSound
    var symbol: String
    var hue: Double
    var photo: Data?
    var preAlarmMinutes: Int
    var autoSnoozeMinutes: Int
    var autoSnoozeTimes: Int
    var snoozeMinutes: Int
    var isCritical: Bool
    var criticalVolume: Double
    var showsInCalendar = true

    /// Starting values for a new reminder of a kind.
    init(kind: ReminderKind, start: Date) {
        let calendar = Calendar.current
        let now = calendar.component(.hour, from: .now) * 60 + calendar.component(.minute, from: .now)
        rule = ScheduleRule(kind: kind, start: start, times: [kind == .wakeUp ? 7 * 60 : now])
        rule.weekdays = kind == .wakeUp ? [2, 3, 4, 5, 6] : [calendar.component(.weekday, from: start)]
        rule.monthDays = [calendar.component(.day, from: start)]
        rule.nthWeekday = calendar.component(.weekday, from: start)
        message = kind == .wakeUp ? "Wake up" : ""
        notes = ""
        sound = kind == .wakeUp ? .rise : .chime
        symbol = kind == .wakeUp ? "sun.max.fill" : "bell.fill"
        hue = kind == .wakeUp ? 0.12 : 0.48
        photo = nil
        preAlarmMinutes = 0
        autoSnoozeMinutes = kind == .wakeUp ? 9 : 0
        autoSnoozeTimes = 3
        snoozeMinutes = kind == .wakeUp ? 9 : 10
        isCritical = false
        criticalVolume = 0.8
    }

    init(_ reminder: Reminder) {
        rule = reminder.rule
        message = reminder.message
        notes = reminder.notes
        sound = reminder.sound
        symbol = reminder.symbol
        hue = reminder.hue
        photo = reminder.photo
        preAlarmMinutes = reminder.preAlarmMinutes
        autoSnoozeMinutes = reminder.autoSnoozeMinutes
        autoSnoozeTimes = reminder.autoSnoozeTimes
        snoozeMinutes = reminder.snoozeMinutes
        isCritical = reminder.isCritical
        criticalVolume = reminder.criticalVolume
        showsInCalendar = reminder.showsInCalendar
    }

    func apply(to reminder: Reminder) {
        reminder.rule = rule
        reminder.message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.sound = sound
        reminder.symbol = symbol
        reminder.hue = hue
        reminder.photo = photo
        reminder.preAlarmMinutes = preAlarmMinutes
        reminder.autoSnoozeMinutes = autoSnoozeMinutes
        reminder.autoSnoozeTimes = autoSnoozeTimes
        reminder.snoozeMinutes = snoozeMinutes
        reminder.isCritical = isCritical
        reminder.criticalVolume = criticalVolume
        reminder.showsInCalendar = showsInCalendar
    }

    /// What needs fixing before it can be saved, or nil when it's ready.
    var problem: String? {
        let kind = rule.kind
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Add a message so you know what the reminder is for."
        }
        if kind.allowsHourlyTimes && rule.timeMode == .everyHours {
            if rule.toMinute < rule.fromMinute { return "The Until time must be after the From time." }
        } else if rule.times.isEmpty {
            return "Add at least one time."
        }
        if (kind == .weekly || kind == .wakeUp) && rule.weekdays.isEmpty {
            return "Pick at least one day of the week."
        }
        if kind == .monthly && rule.monthlyMode == .days && rule.monthDays.isEmpty {
            return "Pick at least one day of the month."
        }
        if kind.repeats && rule.endMode == .endDate, let end = rule.endDate, end < rule.start {
            return "The end date is before the start date."
        }
        return nil
    }
}

/// Adds or edits a reminder.
struct ReminderFormView: View {
    private let existing: Reminder?
    /// The ring this edit was opened from, if any.
    private let occurrence: Occurrence?
    private let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var draft: ReminderDraft
    @State private var problem: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var pendingMove: PendingMove?

    /// One ring of a repeating reminder that the edit would move, while we ask how far the edit goes.
    private struct PendingMove {
        let occurrence: Occurrence
        let target: Date
    }

    /// Edits an existing reminder, in its own sheet.
    init(reminder: Reminder, occurrence: Occurrence? = nil) {
        existing = reminder
        self.occurrence = occurrence
        onSaved = {}
        _draft = State(initialValue: ReminderDraft(reminder))
    }

    /// Adds a new reminder of a kind, pushed from the type picker.
    init(newKind kind: ReminderKind, startDay: Date, onSaved: @escaping () -> Void) {
        existing = nil
        occurrence = nil
        self.onSaved = onSaved
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let start = max(today, calendar.startOfDay(for: startDay))
        _draft = State(initialValue: ReminderDraft(kind: kind, start: start))
    }

    var body: some View {
        if existing == nil {
            form
        } else {
            NavigationStack { form }
        }
    }

    private var form: some View {
        Form {
            if let problem {
                Section {
                    Label(problem, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
            typeSection
            aboutSection
            whenSection
            Section {
                Toggle("Show in Calendar", isOn: $draft.showsInCalendar)
            } footer: {
                Text("Turn off to keep it out of the Calendar tab. It still rings and shows on the Days tab.")
            }
            if draft.rule.kind.repeats { endSection }
            alertSection
            pictureSection
        }
        .ringletBackground()
        .navigationTitle(existing == nil ? "New \(draft.rule.kind.title)" : "Edit Reminder")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if existing != nil {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).fontWeight(.semibold)
            }
        }
        .alert("Change this repeating reminder?",
               isPresented: Binding(get: { pendingMove != nil }, set: { if !$0 { pendingMove = nil } }),
               presenting: pendingMove) { move in
            Button("This Occurrence Only") { saveOccurrence(move) }
            Button("Update Permanently") { commit() }
            Button("Cancel", role: .cancel) {}
        } message: { move in
            Text("This occurrence moves from \(Self.moveText(move.occurrence.date)) to \(Self.moveText(move.target)). Updating permanently changes every future one too. Other changes, like the message, apply to all of them.")
        }
        .onChange(of: draft.rule.kind) {
            if draft.rule.kind == .wakeUp {
                draft.rule.times = Array(draft.rule.times.prefix(1))
                if draft.rule.weekdays.isEmpty { draft.rule.weekdays = [2, 3, 4, 5, 6] }
            }
            if draft.rule.times.isEmpty { draft.rule.times = [9 * 60] }
        }
        .onChange(of: photoItem) {
            guard let photoItem else { return }
            Task {
                if let data = try? await photoItem.loadTransferable(type: Data.self) {
                    draft.photo = PhotoResizer.jpeg(from: data)
                }
            }
        }
        .onDisappear { SoundPlayer.shared.stop() }
    }

    // MARK: Sections

    private var typeSection: some View {
        Section {
            Picker("Type", selection: $draft.rule.kind) {
                ForEach(ReminderKind.allCases) { Text($0.title).tag($0) }
            }
            if let unit = draft.rule.kind.intervalUnit {
                Picker("Repeats", selection: $draft.rule.interval) {
                    ForEach([1, 2, 3, 4, 5, 6, 7, 10, 12, 14, 30], id: \.self) { n in
                        Text(n == 1 ? "Every \(unit)" : "Every \(n) \(unit)s").tag(n)
                    }
                }
            }
        } footer: {
            Text("Rings: \(draft.rule.summary), \(draft.rule.timesSummary)")
        }
    }

    private var aboutSection: some View {
        Section {
            TextField(draft.rule.kind == .wakeUp ? "Wake up" : "Message, e.g. Take medication", text: $draft.message)
                .font(.headline)
            TextField("Notes", text: $draft.notes, axis: .vertical)
                .lineLimit(2...6)
            HStack {
                Picker("Sound", selection: $draft.sound) {
                    ForEach(ReminderSound.allCases) { Text($0.title).tag($0) }
                }
                Button {
                    SoundPlayer.shared.play(draft.sound, repeating: false)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                }
                .buttonStyle(.borderless)
                .disabled(draft.sound == .silent)
                .accessibilityLabel("Play sound")
            }
        }
    }

    private var pictureSection: some View {
        Section("Image") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                ForEach(ReminderSymbols.all, id: \.symbol) { option in
                    let isChosen = draft.photo == nil && draft.symbol == option.symbol
                    Button {
                        draft.symbol = option.symbol
                        draft.hue = option.hue
                        draft.photo = nil
                        photoItem = nil
                    } label: {
                        ReminderImage(photo: nil, symbol: option.symbol, hue: option.hue, size: 48)
                            .overlay {
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .strokeBorder(Color.highlight, lineWidth: isChosen ? 3 : 0)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.symbol)
                    .accessibilityAddTraits(isChosen ? .isSelected : [])
                }
            }
            .padding(.vertical, 6)

            HStack(spacing: 14) {
                if draft.photo != nil {
                    ReminderImage(photo: draft.photo, symbol: draft.symbol, hue: draft.hue, size: 48)
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(draft.photo == nil ? "Use My Own Photo" : "Choose Another Photo", systemImage: "photo")
                }
                if draft.photo != nil {
                    Spacer()
                    Button("Remove", role: .destructive) {
                        draft.photo = nil
                        photoItem = nil
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    @ViewBuilder
    private var whenSection: some View {
        let kind = draft.rule.kind
        Section("When") {
            DatePicker(kind == .oneTime || kind == .yearly ? "Date" : "Start Date",
                       selection: $draft.rule.start, displayedComponents: .date)

            if kind.allowsHourlyTimes {
                Picker("Times", selection: $draft.rule.timeMode) {
                    Text("Specific Times").tag(TimeMode.specific)
                    Text("Every X Hours").tag(TimeMode.everyHours)
                }
                .pickerStyle(.segmented)
            }

            if kind.allowsHourlyTimes && draft.rule.timeMode == .everyHours {
                Stepper("Every \(draft.rule.everyHours) hour\(draft.rule.everyHours == 1 ? "" : "s")",
                        value: $draft.rule.everyHours, in: 1...12)
                DatePicker("From", selection: minuteBinding(\.fromMinute), displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: minuteBinding(\.toMinute), displayedComponents: .hourAndMinute)
            } else {
                ForEach(Array(draft.rule.times.enumerated()), id: \.offset) { index, _ in
                    HStack {
                        DatePicker(kind == .wakeUp ? "Alarm Time" : "Time \(index + 1)",
                                   selection: timeBinding(index), displayedComponents: .hourAndMinute)
                        if draft.rule.times.count > 1 {
                            Button {
                                guard index < draft.rule.times.count else { return }
                                draft.rule.times.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove time \(index + 1)")
                        }
                    }
                }
                if kind != .wakeUp {
                    Button {
                        let last = draft.rule.times.last ?? 8 * 60
                        draft.rule.times.append((last + 60) % (24 * 60))
                    } label: {
                        Label("Add Time", systemImage: "plus.circle.fill")
                    }
                }
            }

            if kind == .weekly || kind == .wakeUp {
                WeekdayChips(selection: $draft.rule.weekdays)
                if kind == .wakeUp {
                    HStack {
                        Button("Weekdays") { draft.rule.weekdays = [2, 3, 4, 5, 6] }
                        Button("Weekends") { draft.rule.weekdays = [1, 7] }
                        Button("Every Day") { draft.rule.weekdays = Set(1...7) }
                    }
                    .buttonStyle(.bordered)
                    .font(.footnote)
                }
            }

            if kind == .monthly {
                Picker("Repeat on", selection: $draft.rule.monthlyMode) {
                    Text("Days of Month").tag(MonthlyMode.days)
                    Text("Day of Week").tag(MonthlyMode.weekday)
                }
                .pickerStyle(.segmented)
                if draft.rule.monthlyMode == .days {
                    MonthDayChips(selection: $draft.rule.monthDays)
                } else {
                    Picker("Which", selection: $draft.rule.nthWeek) {
                        ForEach([1, 2, 3, 4, -1], id: \.self) { Text(ScheduleRule.ordinal($0)).tag($0) }
                    }
                    Picker("Day", selection: $draft.rule.nthWeekday) {
                        ForEach(1...7, id: \.self) { Text(Calendar.current.weekdaySymbols[$0 - 1]).tag($0) }
                    }
                }
            }

            if kind == .cycle {
                Stepper("\(draft.rule.cycleOn) days on", value: $draft.rule.cycleOn, in: 1...365)
                Stepper("\(draft.rule.cycleOff) days off", value: $draft.rule.cycleOff, in: 0...365)
            }
        }
    }

    private var endSection: some View {
        Section {
            Picker("Ends", selection: $draft.rule.endMode) {
                Text("End Date").tag(EndMode.endDate)
                Text("Total Days").tag(EndMode.totalDays)
            }
            .pickerStyle(.segmented)
            if draft.rule.endMode == .endDate {
                Toggle("Runs Forever", isOn: Binding(
                    get: { draft.rule.endDate == nil },
                    set: { forever in
                        draft.rule.endDate = forever ? nil
                            : Calendar.current.date(byAdding: .month, value: 1, to: draft.rule.start)
                    }
                ))
                if draft.rule.endDate != nil {
                    DatePicker("End Date", selection: Binding(
                        get: { draft.rule.endDate ?? draft.rule.start },
                        set: { draft.rule.endDate = $0 }
                    ), in: draft.rule.start..., displayedComponents: .date)
                }
            } else {
                Stepper("Runs for \(draft.rule.totalDays) days", value: $draft.rule.totalDays, in: 1...3650)
            }
        }
    }

    private var alertSection: some View {
        Section {
            LeadTimePicker(minutes: $draft.preAlarmMinutes)
            Picker("Auto-Snooze", selection: $draft.autoSnoozeMinutes) {
                Text("Off").tag(0)
                ForEach([5, 9, 10, 15, 30], id: \.self) { Text("Every \($0) min").tag($0) }
            }
            if draft.autoSnoozeMinutes > 0 {
                Stepper("Up to \(draft.autoSnoozeTimes) more time\(draft.autoSnoozeTimes == 1 ? "" : "s")",
                        value: $draft.autoSnoozeTimes, in: 1...5)
            }
            Picker("Snooze Button", selection: $draft.snoozeMinutes) {
                ForEach([5, 9, 10, 15, 30, 60], id: \.self) { Text("\($0) min").tag($0) }
            }
            Toggle("Critical Alert", isOn: $draft.isCritical)
            if draft.isCritical {
                HStack {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $draft.criticalVolume, in: 0.1...1, step: 0.05)
                    Text(draft.criticalVolume.formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
            }
        } header: {
            Text("Alerts")
        } footer: {
            Text("Auto-snooze rings again until you mark the reminder done. A critical alert gets through Focus modes and plays at the volume you set here.")
        }
    }

    // MARK: Helpers

    private func timeBinding(_ index: Int) -> Binding<Date> {
        Binding(
            get: { index < draft.rule.times.count ? Self.date(fromMinute: draft.rule.times[index]) : .now },
            set: { if index < draft.rule.times.count { draft.rule.times[index] = Self.minute(from: $0) } }
        )
    }

    private func minuteBinding(_ keyPath: WritableKeyPath<ScheduleRule, Int>) -> Binding<Date> {
        Binding(
            get: { Self.date(fromMinute: draft.rule[keyPath: keyPath]) },
            set: { draft.rule[keyPath: keyPath] = Self.minute(from: $0) }
        )
    }

    static func date(fromMinute minute: Int) -> Date {
        Calendar.current.date(byAdding: .minute, value: minute, to: Calendar.current.startOfDay(for: .now)) ?? .now
    }

    static func minute(from date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private func save() {
        if let problem = draft.problem {
            withAnimation { self.problem = problem }
            return
        }
        if let move = occurrenceMove() {
            pendingMove = move
        } else {
            commit()
        }
    }

    /// The ring that would move if this edit changes a repeating reminder's day or time, or nil
    /// when "this occurrence only" wouldn't mean anything.
    private func occurrenceMove() -> PendingMove? {
        guard let existing, existing.kind.repeats, draft.rule.kind == existing.kind,
              let ring = occurrence ?? nextRing(of: existing),
              let original = Planner.parse(ring.key)?.date
        else { return nil }
        let target = draft.rule.movedRing(original, from: existing.rule)
        return target == original ? nil : PendingMove(occurrence: ring, target: target)
    }

    private func nextRing(of reminder: Reminder) -> Occurrence? {
        let calendar = Calendar.current
        let marks = Planner.marksByKey((try? modelContext.fetch(FetchDescriptor<OccurrenceMark>())) ?? [])
        let today = calendar.startOfDay(for: .now)
        for offset in 0..<min(4000, 366 * max(1, reminder.interval) + 7) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { break }
            let rings = Planner.occurrences(on: day, reminders: [reminder], marks: marks, includeTurnedOff: true)
            if let ring = rings.first(where: { $0.date >= .now }) { return ring }
        }
        return nil
    }

    /// Keeps the schedule as it was and moves only this ring. Everything else on the form still applies.
    private func saveOccurrence(_ move: PendingMove) {
        guard let existing else { return }
        var kept = draft
        kept.rule = existing.rule
        let mark = OccurrenceMark.findOrInsert(move.occurrence.key, in: modelContext)
        mark.movedTo = move.target
        mark.isDone = false
        NotificationScheduler.clear(key: move.occurrence.key)
        finishSaving(kept, to: existing)
    }

    private func commit() {
        let reminder: Reminder
        if let existing {
            reminder = existing
        } else {
            reminder = Reminder(kind: draft.rule.kind)
            modelContext.insert(reminder)
        }
        finishSaving(draft, to: reminder)
    }

    private func finishSaving(_ values: ReminderDraft, to reminder: Reminder) {
        values.apply(to: reminder)
        try? modelContext.save()
        followToNewDay(reminder)
        let context = modelContext
        Task {
            _ = await NotificationScheduler.requestAuthorization()
            await NotificationScheduler.reschedule(context: context)
        }
        SoundPlayer.shared.stop()
        onSaved()
        dismiss()
    }

    /// If the edit took this reminder off the day showing on the Days tab, goes to where it now
    /// rings, so it doesn't look like it disappeared.
    private func followToNewDay(_ reminder: Reminder) {
        let router = AppRouter.shared
        guard occurrence != nil, router.tab == .days else { return }
        let marks = Planner.marksByKey((try? modelContext.fetch(FetchDescriptor<OccurrenceMark>())) ?? [])
        let stillHere = !Planner.occurrences(on: router.day, reminders: [reminder], marks: marks).isEmpty
        if !stillHere, let next = nextRing(of: reminder) {
            router.day = Calendar.current.startOfDay(for: next.date)
        }
    }

    private static func moveText(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }
}

/// Seven toggles, Monday first.
struct WeekdayChips: View {
    @Binding var selection: Set<Int>

    var body: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        HStack(spacing: 6) {
            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(symbols[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .background(isOn ? Color.accentColor : Color.secondary.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

/// Days 1 to 31 plus Last.
struct MonthDayChips: View {
    @Binding var selection: Set<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(Array(1...31) + [ScheduleRule.lastDayOfMonth], id: \.self) { day in
                    let isOn = selection.contains(day)
                    Button {
                        if isOn { selection.remove(day) } else { selection.insert(day) }
                    } label: {
                        Text(day == ScheduleRule.lastDayOfMonth ? "Last" : "\(day)")
                            .font(.footnote.weight(.semibold))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .foregroundStyle(isOn ? Color.white : Color.primary)
                            .background(isOn ? Color.accentColor : Color.secondary.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            Text("Months without a 29th, 30th or 31st skip that day. Pick Last for the final day of every month.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// Pre-alarm lead time as a number and a unit, picked on two wheels. "-" turns it off.
private struct LeadTimePicker: View {
    @Binding var minutes: Int
    @State private var isExpanded = false
    /// The unit picked on the wheel, so 60 minutes stays "60 Minutes" instead of jumping to "1 Hour".
    @State private var pickedUnit: Unit?

    private enum Unit: Int, CaseIterable, Identifiable {
        case minute = 1, hour = 60, day = 1440, week = 10080

        var id: Self { self }

        func name(_ count: Int) -> String {
            let word = switch self {
            case .minute: "Minute"
            case .hour: "Hour"
            case .day: "Day"
            case .week: "Week"
            }
            return count == 1 ? word : word + "s"
        }
    }

    var body: some View {
        Button {
            withAnimation { isExpanded.toggle() }
        } label: {
            LabeledContent("Pre-Alarm") {
                Text(minutes == 0 ? "Off" : "\(count) \(unit.name(count)) before")
                    .foregroundStyle(isExpanded ? Color.accentColor : Color.secondary)
            }
        }
        .tint(.primary)

        if isExpanded {
            HStack(spacing: 0) {
                Picker("Number", selection: countBinding) {
                    Text("-").tag(0)
                    ForEach(1...60, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("Unit", selection: unitBinding) {
                    ForEach(Unit.allCases) { Text($0.name(max(count, 1))).tag($0) }
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(height: 160)
        }
    }

    /// The picked unit, or else the largest unit that divides the minutes exactly.
    private var unit: Unit {
        if let pickedUnit, minutes % pickedUnit.rawValue == 0 { return pickedUnit }
        return Unit.allCases.reversed().first { minutes > 0 && minutes % $0.rawValue == 0 } ?? .minute
    }

    private var count: Int { minutes / unit.rawValue }

    private var countBinding: Binding<Int> {
        Binding(get: { count }, set: { minutes = $0 * unit.rawValue })
    }

    private var unitBinding: Binding<Unit> {
        Binding(get: { unit }, set: {
            minutes = max(count, 1) * $0.rawValue
            pickedUnit = $0
        })
    }
}
