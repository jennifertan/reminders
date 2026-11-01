import SwiftUI

/// The first step of adding a reminder: pick what kind it is.
struct TypePickerView: View {
    /// The day the new reminder starts on, usually the day you were looking at.
    let startDay: Date
    @Environment(\.dismiss) private var dismiss
    @State private var picked: ReminderKind?

    var body: some View {
        NavigationStack {
            List(ReminderKind.allCases) { kind in
                Button { picked = kind } label: {
                    HStack(spacing: 14) {
                        Image(systemName: kind.symbol)
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 44, height: 44)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(kind.title).font(.headline).foregroundStyle(Color.heading)
                            ForEach(kind.examples, id: \.self) { example in
                                Text("e.g. \(example)").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .ringletBackground()
            .navigationTitle("New Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .navigationDestination(item: $picked) { kind in
                ReminderFormView(newKind: kind, startDay: startDay) { dismiss() }
            }
        }
    }
}
