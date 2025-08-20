//
//  ContentViews.swift (v13)
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Exercise.createdAt, order: .forward)]) private var exercises: [Exercise]
    @Query private var settingsArray: [AppSettings]

    @State private var showingAdd = false
    @State private var showingLogFor: Exercise? = nil
    @State private var showingSettings = false
    @State private var showingUpgradeAlert = false
    @State private var editingExercise: Exercise? = nil
    @State private var editingGoal: Exercise? = nil
    @State private var showingMacroFor: Exercise? = nil
    @State private var showingSaved = false
    @State private var showingGraphFor: Exercise? = nil

    private var settings: AppSettings? { settingsArray.first }
    private var palette: ThemePalette { ThemeKit.palette(settings) }
    private var isDark: Bool { ThemeKit.isDark(settings) }

    @ViewBuilder
    private var mainContent: some View {
        if exercises.isEmpty {
            ContentUnavailableView("No Exercises", systemImage: "figure.strengthtraining.traditional", description: Text("Add an exercise with a daily rep goal to get started."))
        } else {
            List {
                ForEach(exercises) { ex in
                    ExerciseRow(exercise: ex, palette: palette)
                        .contentShape(Rectangle())
                        .onTapGesture { showingLogFor = ex }
                        .contextMenu {
                            Button("Change Daily Goal") { editingGoal = ex }
                            Button("Log Today's Reps") { showingLogFor = ex }
                            Button("Edit Schedule") { editingExercise = ex }
                            Button("Plan Macro Goal") { showingMacroFor = ex }
                            Button("View Progress Graph") { showingGraphFor = ex }
                        }
                        .swipeActions(edge: .trailing) { Button("Log") { showingLogFor = ex }.tint(palette.onTint) }
                        .swipeActions(edge: .leading) { Button("Edit") { editingExercise = ex }.tint(.blue) }
                        .listRowBackground(Color.clear)
                }
                .onDelete { indexSet in
                    for i in indexSet { context.delete(exercises[i]) }
                    LocalReminderScheduler.rescheduleAll(using: context)
                }
            }.listStyle(.plain)
        }
    }

    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle("RepGoal")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button { LocalReminderScheduler.rescheduleAll(using: context) } label: { Image(systemName: "bell.badge") } }
                    ToolbarItem(placement: .topBarTrailing) { Button { showingSaved = true } label: { Image(systemName: "bookmark") } }
                    ToolbarItem(placement: .topBarTrailing) { Button { showingSettings = true } label: { Image(systemName: "gearshape") } }
                    ToolbarItem(placement: .topBarTrailing) { Button { showingAdd = true } label: { Image(systemName: "plus") } }
                }
                .sheet(isPresented: $showingAdd) { AddExerciseView(palette: palette).themed(palette: palette, isDark: isDark) }
                .sheet(isPresented: $showingSettings) { SettingsView().themed(palette: ThemeKit.palette(settings), isDark: ThemeKit.isDark(settings)) }
                .sheet(isPresented: $showingSaved) { SavedMacrosView().themed(palette: palette, isDark: isDark) }
                .sheet(item: $showingLogFor) { ex in LogRepsView(exercise: ex, palette: palette).themed(palette: palette, isDark: isDark) }
                .sheet(item: $editingExercise) { ex in EditExerciseView(exercise: ex, palette: palette).themed(palette: palette, isDark: isDark) }
                .sheet(item: $editingGoal) { ex in GoalEditorView(exercise: ex, palette: palette).themed(palette: palette, isDark: isDark) }
                .sheet(item: $showingMacroFor) { ex in MacroPlannerView(exercise: ex, palette: palette).themed(palette: palette, isDark: isDark) }
                .sheet(item: $showingGraphFor) { ex in ProgressGraphView(exercise: ex, palette: palette).themed(palette: palette, isDark: isDark) }
        }
        .themed(palette: palette, isDark: isDark)
        .task { LocalReminderScheduler.rescheduleAll(using: context) }
        .onChange(of: exercises.count) { _ in LocalReminderScheduler.rescheduleAll(using: context) }
    }
}

struct ExerciseRow: View {
    @Environment(\.modelContext) private var context
    let exercise: Exercise
    let palette: ThemePalette
    @State private var todayTotal: Int = 0

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name).font(.headline)
                Text("Daily goal: \(exercise.dailyGoal)").font(.caption).foregroundStyle(.secondary)
                WeekdayStripe(scheduled: exercise.scheduledWeekdays, palette: palette)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                ProgressView(value: Double(todayTotal), total: Double(exercise.dailyGoal)).frame(width: 120)
                Text("\(todayTotal)/\(exercise.dailyGoal)").monospacedDigit()
            }
        }
        .task(id: exercise.id) { await refreshProgress() }
        .onReceive(NotificationCenter.default.publisher(for: .repEntryUpdated)) { note in
            if let id = note.object as? UUID, id == exercise.id { Task { await refreshProgress() } }
        }
        .listRowBackground(Color.clear)
    }

    @MainActor
    private func refreshProgress() async {
        do { todayTotal = try DataService.todaysProgress(for: exercise, context: context) } catch { todayTotal = 0 }
    }
}

struct WeekdayStripe: View {
    let scheduled: [Int]
    let palette: ThemePalette
    private let symbols: [String] = DateFormatter().veryShortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
    private let indices: [Int] = Array(0 ..< 7)
    var body: some View {
        HStack(spacing: 4) {
            ForEach(indices, id: \.self) { i in
                let on = scheduled.contains(i + 1)
                Text(symbols[i]).font(.caption2).fontWeight(on ? .semibold : .regular).foregroundStyle(on ? palette.onTint : palette.offTint)
            }
        }
    }
}
