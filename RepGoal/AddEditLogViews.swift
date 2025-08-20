//
//  AddEditLogViews.swift (v14)
import SwiftData
import SwiftUI

struct AddExerciseView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let palette: ThemePalette

    @State private var name: String = ""
    @State private var goal: Int = 100
    @State private var selectedDays: Set<Int> = Set(1...7)
    private let weekDays = Array(1...7)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g., Push‑ups)", text: $name)
                } header: { AppStyle.header("Exercise") }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Stepper(value: $goal, in: 1...10000, step: 5) {
                            HStack { Text("Reps per day"); Spacer(); Text("\(goal)").monospacedDigit().foregroundStyle(.secondary) }
                        }
                        HStack {
                            Button("+5") { goal = min(10000, goal + 5) }.buttonStyle(BorderedButtonStyle())
                            Button("+10") { goal = min(10000, goal + 10) }.buttonStyle(BorderedButtonStyle())
                        }
                    }
                } header: { AppStyle.header("Goal (per active day)") }

                Section {
                    HStack(spacing: 6) {
                        ForEach(weekDays, id: \.self) { d in
                            let on = selectedDays.contains(d)
                            Button(shortLabel(for: d)) {
                                if on { selectedDays.remove(d) } else { selectedDays.insert(d) }
                            }
                            .buttonStyle(BorderedButtonStyle())
                            .tint(on ? palette.onTint : palette.offTint)
                        }
                    }
                    Text("Choose the days this goal is active.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: { AppStyle.header("Schedule") }
            }
            .navigationTitle("New Exercise")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedDays.isEmpty)
                }
            }
        }
    }

    private func save() {
        let ex = Exercise(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            dailyGoal: goal,
            scheduledWeekdays: Array(selectedDays).sorted()
        )
        context.insert(ex)
        try? context.save()
        LocalReminderScheduler.rescheduleAll(using: context)
        dismiss()
    }

    private func shortLabel(for weekday: Int) -> String {
        let syms = DateFormatter().veryShortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        return syms[(weekday - 1 + syms.count) % syms.count]
    }
}

struct GoalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var exercise: Exercise
    let palette: ThemePalette

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Stepper(value: $exercise.dailyGoal, in: 1...10000, step: 5) {
                            HStack { Text("Reps per day"); Spacer(); Text("\(exercise.dailyGoal)").monospacedDigit().foregroundStyle(.secondary) }
                        }
                        HStack {
                            Button("+5") { exercise.dailyGoal = min(10000, exercise.dailyGoal + 5) }.buttonStyle(BorderedButtonStyle())
                            Button("+10") { exercise.dailyGoal = min(10000, exercise.dailyGoal + 10) }.buttonStyle(BorderedButtonStyle())
                        }
                    }
                    Text("Changing the goal updates your progress bar immediately.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: { AppStyle.header("Daily Goal") }
            }
            .navigationTitle("Daily Goal")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Save") { dismiss() } }
            }
        }
    }
}

struct EditExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var exercise: Exercise
    let palette: ThemePalette
    private let weekDays = Array(1...7)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $exercise.name)
                } header: { AppStyle.header("Exercise") }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Stepper(value: $exercise.dailyGoal, in: 1...10000, step: 5) {
                            HStack { Text("Reps per day"); Spacer(); Text("\(exercise.dailyGoal)").monospacedDigit().foregroundStyle(.secondary) }
                        }
                        HStack {
                            Button("+5") { exercise.dailyGoal = min(10000, exercise.dailyGoal + 5) }.buttonStyle(BorderedButtonStyle())
                            Button("+10") { exercise.dailyGoal = min(10000, exercise.dailyGoal + 10) }.buttonStyle(BorderedButtonStyle())
                        }
                    }
                } header: { AppStyle.header("Goal (per active day)") }

                Section {
                    HStack(spacing: 6) {
                        ForEach(weekDays, id: \.self) { d in
                            let on = exercise.scheduledWeekdays.contains(d)
                            Button(shortLabel(for: d)) {
                                var set = Set(exercise.scheduledWeekdays)
                                if on { set.remove(d) } else { set.insert(d) }
                                exercise.scheduledWeekdays = Array(set).sorted()
                            }
                            .buttonStyle(BorderedButtonStyle())
                            .tint(on ? palette.onTint : palette.offTint)
                        }
                    }
                    Text("Choose the days this goal is active.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: { AppStyle.header("Schedule") }
            }
            .navigationTitle("Edit Exercise")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        try? context.save()
                        LocalReminderScheduler.rescheduleAll(using: context)
                        dismiss()
                    }
                }
            }
        }
    }

    private func shortLabel(for weekday: Int) -> String {
        let syms = DateFormatter().veryShortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        return syms[(weekday - 1 + syms.count) % syms.count]
    }
}

struct LogRepsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let exercise: Exercise
    let palette: ThemePalette
    @State private var currentTotal: Int = 0
    @FocusState private var valueFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Name", value: exercise.name)
                    LabeledContent("Daily Goal", value: String(exercise.dailyGoal))
                } header: { AppStyle.header("Exercise") }

                Section {
                    TextField("Enter today's total", value: $currentTotal, format: .number)
                        .keyboardType(.numberPad)
                        .focused($valueFieldFocused)
                    Stepper(value: $currentTotal, in: 0...100000, step: 1) {
                        HStack { Text("Current total today"); Spacer(); Text("\(currentTotal)").monospacedDigit().foregroundStyle(.secondary) }
                    }
                    HStack {
                        Button("+5") { currentTotal = min(100000, currentTotal + 5) }.buttonStyle(BorderedButtonStyle())
                        Button("+10") { currentTotal = min(100000, currentTotal + 10) }.buttonStyle(BorderedButtonStyle())
                        Spacer()
                        Button("Reset") { currentTotal = 0 }.buttonStyle(BorderedButtonStyle())
                    }
                    Text("Tip: enter the total you've done *so far* today (not the increment).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: { AppStyle.header("Log Progress") }
            }
            .navigationTitle("Log Reps")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close", action: { dismiss() }) }
                ToolbarItem(placement: .topBarTrailing) { Button("Save", action: upsertSave) }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { valueFieldFocused = false } }
            }
        }
        .onAppear { preload() }
    }

    private func preload() {
        do {
            currentTotal = try DataService.todaysProgress(for: exercise, context: context)
        } catch { currentTotal = 0 }
    }

    private func upsertSave() {
        let now = Date()
        let cal = Calendar.current
        let (start, end) = cal.dayBounds(for: now)
        let exID = exercise.id

        let predicate = #Predicate<RepEntry> { entry in
            entry.exercise?.id == exID && entry.date >= start && entry.date < end
        }
        var desc = FetchDescriptor<RepEntry>(predicate: predicate, sortBy: [SortDescriptor(\RepEntry.date, order: .forward)])

        do {
            let todays = try context.fetch(desc)
            if let existing = todays.last {
                existing.currentTotal = currentTotal
                existing.date = now
            } else {
                let entry = RepEntry(currentTotal: currentTotal, date: now, exercise: exercise)
                context.insert(entry)
            }
            try? context.save()
        } catch {
            let entry = RepEntry(currentTotal: currentTotal, date: now, exercise: exercise)
            context.insert(entry); try? context.save()
        }
        NotificationCenter.default.post(name: .repEntryUpdated, object: exercise.id)
        LocalReminderScheduler.rescheduleAll(using: context)
        dismiss()
    }
}
