import SwiftData
import SwiftUI

/// A month at a glance. Days get a dot per reminder in its picture color (red when missed); tap a day to see its list.
struct CalendarView: View {
    @Query private var reminders: [Reminder]
    @Query private var marks: [OccurrenceMark]
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var selected = Calendar.current.startOfDay(for: .now)
    @State private var isAdding = false
    @State private var isShowingSettings = false
    @State private var actions = OccurrenceActions()
    /// Comma-separated kinds the calendar leaves out.
    @AppStorage("calendarHiddenKinds") private var hiddenKindsRaw = ""

    var body: some View {
        List {
            Section {
                MonthGrid(month: $month, selected: $selected, reminders: shownReminders, marks: Planner.marksByKey(marks))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 12, trailing: 8))
            }
            if !hiddenKinds.isEmpty {
                Section {
                    HStack {
                        Label("Hiding \(hiddenKindNames)", systemImage: "line.3.horizontal.decrease.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Show All") { hiddenKinds = [] }
                            .font(.footnote.weight(.semibold))
                            .buttonStyle(.borderless)
                    }
                }
            }
            OccurrenceList(day: selected, actions: $actions, hiddenKinds: hiddenKinds, isCalendar: true)
        }
        .occurrenceActions($actions)
        .ringletBackground()
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { isShowingSettings = true } label: { Label("Settings", systemImage: "gearshape") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Show in Calendar") {
                        ForEach(ReminderKind.allCases) { kind in
                            Toggle(kind.title, isOn: shows(kind))
                        }
                    }
                    Button("One-Time Only") {
                        hiddenKinds = Set(ReminderKind.allCases.filter { $0 != .oneTime })
                    }
                    Button("Show Everything") { hiddenKinds = [] }
                } label: {
                    Label("Filter", systemImage: hiddenKinds.isEmpty
                          ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                AddButton { isAdding = true }
            }
        }
        .sheet(isPresented: $isAdding) { TypePickerView(startDay: selected) }
        .sheet(isPresented: $isShowingSettings) { SettingsView() }
    }

    private var hiddenKinds: Set<ReminderKind> {
        get { Set(hiddenKindsRaw.split(separator: ",").compactMap { ReminderKind(rawValue: String($0)) }) }
        nonmutating set { hiddenKindsRaw = newValue.map(\.rawValue).sorted().joined(separator: ",") }
    }

    private var hiddenKindNames: String {
        ReminderKind.allCases.filter(hiddenKinds.contains).map(\.title).joined(separator: ", ")
    }

    private var shownReminders: [Reminder] {
        reminders.filter { $0.showsInCalendar && !hiddenKinds.contains($0.kind) }
    }

    private func shows(_ kind: ReminderKind) -> Binding<Bool> {
        Binding(
            get: { !hiddenKinds.contains(kind) },
            set: { isShown in
                if isShown { hiddenKinds.remove(kind) } else { hiddenKinds.insert(kind) }
            }
        )
    }
}

private struct MonthGrid: View {
    @Binding var month: Date
    @Binding var selected: Date
    let reminders: [Reminder]
    let marks: [String: OccurrenceMark]
    @Environment(\.colorScheme) private var colorScheme

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button { shift(-1) } label: {
                    Image(systemName: "chevron.left").font(.headline).frame(width: 44, height: 36)
                }
                .accessibilityLabel("Previous month")
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.heading)
                Spacer()
                Button { shift(1) } label: {
                    Image(systemName: "chevron.right").font(.headline).frame(width: 44, height: 36)
                }
                .accessibilityLabel("Next month")
            }
            .buttonStyle(.borderless)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdayHeaders, id: \.self) { name in
                    Text(name.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                ForEach(days, id: \.self) { day in
                    dayCell(day)
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 40).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 2 else { return }
                shift(value.translation.width < 0 ? 1 : -1)
            }
        )
    }

    private func dayCell(_ day: Date) -> some View {
        let occurrences = Planner.occurrences(on: day, reminders: reminders, marks: marks)
        let isSelected = calendar.isDate(day, inSameDayAs: selected)
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        let isToday = calendar.isDateInToday(day)

        return Button {
            selected = day
            if !inMonth { month = calendar.dateInterval(of: .month, for: day)?.start ?? month }
        } label: {
            VStack(spacing: 4) {
                Text(day.formatted(.dateTime.day()))
                    .font(.body.weight(isToday ? .bold : .regular))
                    .monospacedDigit()
                dots(for: occurrences, isSelected: isSelected)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(isSelected ? Color.white : (inMonth ? Color.primary : Color.secondary.opacity(0.6)))
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            }
            .overlay {
                if isToday && !isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(occurrences.count) reminders")
    }

    /// One dot per reminder that day, up to three, in the color of its picture. Missed ones are red.
    /// When there are more, the rarer ones win, so a daily reminder doesn't crowd out an every-3-weeks
    /// one, and a small plus shows that some were left out.
    private func dots(for occurrences: [Occurrence], isSelected: Bool) -> some View {
        var seen = Set<UUID>()
        let perReminder = occurrences.filter { seen.insert($0.reminder.id).inserted }
        let ranked = perReminder.enumerated().sorted { a, b in
            let ra = Self.rank(a.element), rb = Self.rank(b.element)
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
        let firsts = Array(ranked.prefix(3)).sorted { $0.date < $1.date }
        let hasMore = perReminder.count > firsts.count
        return HStack(spacing: 3) {
            ForEach(firsts, id: \.key) { occurrence in
                Circle()
                    .fill(Planner.status(of: occurrence, marks: marks) == .missed
                          ? Color.red : dotColor(hue: occurrence.reminder.hue))
                    .overlay { if isSelected { Circle().strokeBorder(Color.white, lineWidth: 1) } }
                    .frame(width: 6, height: 6)
            }
            if hasMore {
                Image(systemName: "plus")
                    .font(.system(size: 6, weight: .heavy))
                    .frame(width: 6, height: 6)
            }
        }
        .frame(height: 6)
    }

    /// Lower shows first: reminders that come round least often.
    private static func rank(_ occurrence: Occurrence) -> Int {
        switch occurrence.reminder.kind {
        case .oneTime: 0
        case .yearly: 1
        case .monthly: 2
        case .weekly: 3
        case .cycle: 4
        case .wakeUp: 5
        case .daily: 6
        }
    }

    private func dotColor(hue: Double) -> Color {
        colorScheme == .dark
            ? Color(hue: hue, saturation: 0.55, brightness: 0.95)
            : Color(hue: hue, saturation: 0.75, brightness: 0.7)
    }

    private var weekdayHeaders: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Six full weeks, starting on the week that holds the 1st.
    private var days: [Date] {
        guard let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: month)?.start else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: firstWeek) }
    }

    private func shift(_ months: Int) {
        withAnimation(.snappy) {
            month = calendar.date(byAdding: .month, value: months, to: month) ?? month
        }
    }
}

#Preview {
    NavigationStack { CalendarView() }
        .modelContainer(PreviewContainer.shared)
}
