import SwiftData
import SwiftUI

/// One day's reminders, with arrows to step through the days.
struct DaysView: View {
    @Bindable private var router = AppRouter.shared
    @State private var isAdding = false
    @State private var isShowingSettings = false
    @State private var isShowingHelp = false

    var body: some View {
        List {
            OccurrenceList(day: router.day)
        }
        .ringletBackground()
        .safeAreaInset(edge: .top, spacing: 0) {
            DayPicker(day: $router.day)
        }
        .gesture(
            DragGesture(minimumDistance: 40).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 2 else { return }
                step(value.translation.width < 0 ? 1 : -1)
            }
        )
        .navigationTitle("Days")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { isShowingSettings = true } label: { Label("Settings", systemImage: "gearshape") }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { isShowingHelp = true } label: { Label("Help", systemImage: "questionmark.circle") }
                AddButton { isAdding = true }
            }
        }
        .sheet(isPresented: $isAdding) { TypePickerView(startDay: router.day) }
        .sheet(isPresented: $isShowingSettings) { SettingsView() }
        .sheet(isPresented: $isShowingHelp) { HelpView() }
    }

    private func step(_ days: Int) {
        withAnimation(.snappy) {
            router.day = Calendar.current.date(byAdding: .day, value: days, to: router.day) ?? router.day
        }
    }
}

/// "Today, Sunday, November 1" between previous and next arrows.
struct DayPicker: View {
    @Binding var day: Date

    var body: some View {
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(day)
        HStack {
            Button { move(-1) } label: {
                Image(systemName: "chevron.left").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Previous day")
            Spacer()
            VStack(spacing: 2) {
                Text(relativeName)
                    .font(.headline)
                    .foregroundStyle(Color.heading)
                HStack(spacing: 6) {
                    Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    if !isToday {
                        Button("Today") {
                            withAnimation(.snappy) { day = calendar.startOfDay(for: .now) }
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.highlight)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button { move(1) } label: {
                Image(systemName: "chevron.right").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Next day")
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .background(.bar)
    }

    private var relativeName: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide))
    }

    private func move(_ days: Int) {
        withAnimation(.snappy) {
            day = Calendar.current.date(byAdding: .day, value: days, to: day) ?? day
        }
    }
}

/// The amber plus button used on every tab.
struct AddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.body.weight(.bold))
                .foregroundStyle(.black.opacity(0.8))
                .frame(width: 32, height: 32)
                .background(Color.highlight, in: Circle())
        }
        .accessibilityLabel("Add Reminder")
    }
}

#Preview {
    NavigationStack { DaysView() }
        .modelContainer(PreviewContainer.shared)
}
