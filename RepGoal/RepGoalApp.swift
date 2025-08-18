// RepGoalApp.swift
// iOS 17+ (SwiftUI + SwiftData + BackgroundTasks + Local Notifications)
// ---------------------------------------------------------------------------------
// What this sample does
// - Lets you add exercises with a per‑day rep goal (e.g., 100 push‑ups/day)
// - Lets you log your *current total so far today* at any time
// - Every 3 hours starting at 7:00 AM, a background task computes your remaining reps
//   and fires a local notification for each exercise if you are below goal.
// - Uses SwiftData to persist exercises and daily progress snapshots.
//
// Notes
// - BGTaskScheduler runs at the system’s discretion; exact 3‑hour timing is not guaranteed.
//   The code *chains* one refresh to the next slot (7, 10, 13, 16, 19, 22, then tomorrow 7).
// - Run on a real device to test background delivery; the Simulator throttles/limits BG tasks.
// - Add the Info.plist keys shown at the bottom of this file.
// ---------------------------------------------------------------------------------

import BackgroundTasks
import SwiftData
import SwiftUI
import UserNotifications

// MARK: - SwiftData Models

@Model final class Exercise: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var dailyGoal: Int
    var createdAt: Date

    /// Active weekdays for this goal (1=Sun ... 7=Sat)
    var scheduledWeekdays: [Int]

    @Relationship(deleteRule: .cascade, inverse: \RepEntry.exercise)
    var entries: [RepEntry] = []

    init(name: String, dailyGoal: Int, scheduledWeekdays: [Int] = Array(1...7), id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.dailyGoal = dailyGoal
        self.scheduledWeekdays = scheduledWeekdays
        self.createdAt = createdAt
    }

    func isScheduled(on date: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date) // 1=Sun ... 7=Sat
        return scheduledWeekdays.contains(weekday)
    }
}

/// A snapshot entry of the user's *current total so far today* for a given exercise.
/// If the user logs 40 and later 60, today's progress is 60 (the max of today's entries).
@Model final class RepEntry: Identifiable {
    @Attribute(.unique) var id: UUID
    var date: Date
    var currentTotal: Int

    // Inverse is Exercise.entries
    var exercise: Exercise?

    init(currentTotal: Int, date: Date = Date(), exercise: Exercise?, id: UUID = UUID()) {
        self.id = id
        self.currentTotal = currentTotal
        self.date = date
        self.exercise = exercise
    }
}

// MARK: - Settings Model

@Model final class AppSettings {
    @Attribute(.unique) var id: UUID
    /// 0 = interval (every N hours), 1 = custom times
    var modeRaw: Int
    /// For interval mode: start hour (0-23)
    var startHour: Int
    /// For interval mode: every N hours (1-12)
    var intervalHours: Int
    /// For custom mode: specific hours in the day (0-23)
    var customHours: [Int]
    var createdAt: Date

    init(id: UUID = UUID(), modeRaw: Int = 0, startHour: Int = 7, intervalHours: Int = 3, customHours: [Int] = [7, 10, 13, 16, 19, 22], createdAt: Date = Date()) {
        self.id = id
        self.modeRaw = modeRaw
        self.startHour = startHour
        self.intervalHours = intervalHours
        self.customHours = customHours
        self.createdAt = createdAt
    }

    enum Mode: Int { case interval = 0, custom = 1 }
    var mode: Mode {
        get { Mode(rawValue: modeRaw) ?? .interval }
        set { modeRaw = newValue.rawValue }
    }
}

// MARK: - Calendar helpers

extension Calendar {
    func dayBounds(for date: Date) -> (start: Date, end: Date) {
        let start = startOfDay(for: date)
        let end = self.date(byAdding: .day, value: 1, to: start)!
        return (start, end)
    }
}

// MARK: - Data helpers

enum DataService {
    static func todaysProgress(for exercise: Exercise, context: ModelContext, now: Date = Date()) throws -> Int {
        let cal = Calendar.current
        let (start, end) = cal.dayBounds(for: now)

        let exID = exercise.id
        let predicate = #Predicate<RepEntry> { entry in
            entry.exercise?.id == exID && entry.date >= start && entry.date < end
        }
        var desc = FetchDescriptor<RepEntry>(predicate: predicate, sortBy: [SortDescriptor(\RepEntry.date, order: .forward)])
        desc.propertiesToFetch = [\RepEntry.date, \RepEntry.currentTotal]
        let entries = try context.fetch(desc)
        return entries.last?.currentTotal ?? 0
    }
}

// MARK: - Notifications

extension Notification.Name { static let repEntryUpdated = Notification.Name("RepEntryUpdated") }

// MARK: - Local Reminder Scheduler (fires at exact times without BGTask)

enum LocalReminderScheduler {
    private static func idPrefix(for exercise: Exercise) -> String { "local.\(exercise.id.uuidString)." }
    private static func id(for exercise: Exercise, at date: Date) -> String { idPrefix(for: exercise) + String(Int(date.timeIntervalSince1970)) }

    static func reschedule(for exercise: Exercise, using context: ModelContext, daysAhead: Int = 2) {
        let prefix = idPrefix(for: exercise)
        UNUserNotificationCenter.current().getPendingNotificationRequests { reqs in
            let ids = reqs.filter { $0.identifier.hasPrefix(prefix) }.map { $0.identifier }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
            DispatchQueue.main.async { scheduleUpcoming(for: exercise, using: context, daysAhead: daysAhead) }
        }
    }

    static func rescheduleAll(using context: ModelContext, daysAhead: Int = 2) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { reqs in
            let ids = reqs.filter { $0.identifier.hasPrefix("local.") }.map { $0.identifier }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
            DispatchQueue.main.async {
                do {
                    let all = try context.fetch(FetchDescriptor<Exercise>())
                    for ex in all { scheduleUpcoming(for: ex, using: context, daysAhead: daysAhead) }
                } catch {
                    print("⚠️ rescheduleAll fetch error: \(error)")
                }
            }
        }
    }

    static func scheduleUpcoming(for exercise: Exercise, using context: ModelContext, daysAhead: Int = 2, now: Date = Date()) {
        // Determine candidate hours from settings
        let slots: [Int]
        do {
            let settings = try context.fetch(FetchDescriptor<AppSettings>()).first
            if let s = settings { slots = BackgroundScheduler.computeSlots(from: s) } else { slots = BackgroundScheduler.defaultSlots }
        } catch { slots = BackgroundScheduler.defaultSlots }

        let cal = Calendar.current
        var scheduledCount = 0
        outer: for dayOffset in 0...daysAhead {
            guard let base = cal.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            let weekday = cal.component(.weekday, from: base)
            guard exercise.scheduledWeekdays.contains(weekday) else { continue }
            for h in slots {
                var comps = cal.dateComponents([.year, .month, .day], from: base)
                comps.hour = h; comps.minute = 0; comps.second = 0
                guard let candidate = cal.date(from: comps), candidate > now else { continue }

                // Compute remaining based on progress as of that day (may be full goal if future morning)
                let remaining: Int = {
                    do { return max(0, exercise.dailyGoal - (try DataService.todaysProgress(for: exercise, context: context, now: candidate))) }
                    catch { return exercise.dailyGoal }
                }()
                guard remaining > 0 else { continue }

                let content = UNMutableNotificationContent()
                content.title = exercise.name
                content.body = "You have \(remaining) reps left for today's goal."
                content.sound = .default

                let triggerComps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: candidate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)
                let req = UNNotificationRequest(identifier: id(for: exercise, at: candidate), content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(req)
                scheduledCount += 1
                if scheduledCount >= 16 { break outer } // stay well under the 64 system cap across exercises
            }
        }
    }
}

// MARK: - Background Scheduler

enum BackgroundScheduler {
    /// Update this to match your bundle identifier + a suffix. Also add to Info.plist.
    static let taskIdentifier = "com.example.repgoal.check" // ← CHANGE ME

    static let defaultSlots: [Int] = [7, 10, 13, 16, 19, 22] // 24h clock (fallback)

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            handle(task: task)
        }
    }

    static func scheduleNextCheck(now: Date = Date()) {
        let next = nextCheckDate(after: now)
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = next
        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ Scheduled next check for: \(next)")
        } catch {
            print("⚠️ Failed to schedule BG task: \(error)")
        }
    }

    static func nextCheckDate(after now: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        let slots = loadSlots()

        for h in slots {
            var dc = DateComponents()
            dc.year = comps.year; dc.month = comps.month; dc.day = comps.day
            dc.hour = h; dc.minute = 0; dc.second = 0
            if let d = cal.date(from: dc), d > now { return d }
        }
        // If we're past the last slot, schedule tomorrow at the first slot (07:00 by default)
        var dc = DateComponents()
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        let t = cal.dateComponents([.year, .month, .day], from: tomorrow)
        dc.year = t.year; dc.month = t.month; dc.day = t.day
        dc.hour = (loadSlots().first ?? 7); dc.minute = 0; dc.second = 0
        return cal.date(from: dc)!
    }

    /// Cancel pending and reschedule according to current settings
    static func rescheduleAfterSettingsChange() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        scheduleNextCheck()
    }

    /// Load user-defined slots from SwiftData. Falls back to defaults if none.
    static func loadSlots() -> [Int] {
        do {
            let config = ModelConfiguration("RepGoal")
            let container = try ModelContainer(for: Exercise.self, RepEntry.self, AppSettings.self, configurations: config)
            let context = ModelContext(container)
            let settingsFetch = FetchDescriptor<AppSettings>()
            if let s = try context.fetch(settingsFetch).first {
                return computeSlots(from: s)
            }
        } catch {
            print("⚠️ loadSlots error: \(error)")
        }
        return defaultSlots
    }

    static func computeSlots(from s: AppSettings) -> [Int] {
        switch s.mode {
        case .interval:
            let step = max(1, min(12, s.intervalHours))
            var hours: [Int] = []
            var h = max(0, min(23, s.startHour))
            while h < 24 {
                hours.append(h)
                h += step
            }
            return hours
        case .custom:
            let set = Set(s.customHours.filter { (0...23).contains($0) })
            return Array(set).sorted()
        }
    }

    static func handle(task: BGAppRefreshTask) {
        // Chain the next one immediately to keep the cadence
        scheduleNextCheck()

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        task.expirationHandler = {
            queue.cancelAllOperations()
        }

        queue.addOperation {
            do {
                // Open the same SwiftData store the app uses
                let config = ModelConfiguration("RepGoal")
                let container = try ModelContainer(for: Exercise.self, RepEntry.self, AppSettings.self, configurations: config)
                let context = ModelContext(container)
                try sendNotificationsIfNeeded(using: context)
                task.setTaskCompleted(success: true)
            } catch {
                print("❌ BG task failed: \(error)")
                task.setTaskCompleted(success: false)
            }
        }
    }

    static func sendNotificationsIfNeeded(using context: ModelContext) throws {
        // Keep exact-time reminders in sync via BG refresh instead of firing at opportunistic times.
        LocalReminderScheduler.rescheduleAll(using: context)
    }
}

// MARK: - App Delegate (notifications + BG registration)

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BackgroundScheduler.register()
        requestNotificationAuthorization()
        BackgroundScheduler.scheduleNextCheck()
        // Ensure local reminders are scheduled on launch
        do {
            let config = ModelConfiguration("RepGoal")
            let container = try ModelContainer(for: Exercise.self, RepEntry.self, AppSettings.self, configurations: config)
            let context = ModelContext(container)
            LocalReminderScheduler.rescheduleAll(using: context)
        } catch {
            print("⚠️ Launch reschedule error: \(error)")
        }
        return true
    }

    func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error { print("Notification auth error: \(error)") }
            print("Notifications granted: \(granted)")
        }
    }

    // Show alerts even if the app is foregrounded
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.badge, .sound, .banner, .list])
    }
}

// MARK: - App Entry

@main
struct RepGoalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Use a named configuration so the BG task opens the same store
    private let container: ModelContainer = {
        do {
            let config = ModelConfiguration("RepGoal")
            return try ModelContainer(for: Exercise.self, RepEntry.self, AppSettings.self, configurations: config)
        } catch {
            fatalError("💥 Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Exercise.createdAt, order: .forward)]) private var exercises: [Exercise]

    @State private var showingAdd = false
    @State private var showingLogFor: Exercise? = nil
    @State private var showingSettings = false
    @State private var editingExercise: Exercise? = nil
    @State private var editingGoal: Exercise? = nil

    @ViewBuilder
    private var mainContent: some View {
        if exercises.isEmpty {
            ContentUnavailableView(
                "No Exercises",
                systemImage: "figure.strengthtraining.traditional",
                description: Text("Add an exercise with a daily rep goal to get started.")
            )
        } else {
            List {
                ForEach(exercises) { ex in
                    ExerciseRow(exercise: ex)
                        .contentShape(Rectangle())
                        .onTapGesture { showingLogFor = ex }
                        .contextMenu {
                            Button("Change Daily Goal") { editingGoal = ex }
                            Button("Log Today's Reps") { showingLogFor = ex }
                            Button("Edit Schedule") { editingExercise = ex }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Log") { showingLogFor = ex }
                                .tint(.accentColor)
                        }
                        .swipeActions(edge: .leading) {
                            Button("Edit") { editingExercise = ex }
                                .tint(.blue)
                        }
                }
                .onDelete { indexSet in
                    // Delete exercises and reschedule local reminders
                    for i in indexSet { context.delete(exercises[i]) }
                    LocalReminderScheduler.rescheduleAll(using: context)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle("RepGoal")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            Task { LocalReminderScheduler.rescheduleAll(using: context) }
                        } label: {
                            Image(systemName: "bell.badge")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingAdd = true } label: { Image(systemName: "plus") }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                    }
                }
                .sheet(isPresented: $showingAdd) { AddExerciseView() }
                .sheet(item: $showingLogFor) { ex in LogRepsView(exercise: ex) }
                .sheet(item: $editingExercise) { ex in EditExerciseView(exercise: ex) }
                .sheet(item: $editingGoal) { ex in GoalEditorView(exercise: ex) }
                .sheet(isPresented: $showingSettings) { SettingsView() }
        }
    }
}

struct ExerciseRow: View {
    @Environment(\.modelContext) private var context
    let exercise: Exercise
    @State private var todayTotal: Int = 0

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.headline)
                Text("Daily goal: \(exercise.dailyGoal)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                WeekdayStripe(scheduled: exercise.scheduledWeekdays)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                ProgressView(value: Double(todayTotal), total: Double(exercise.dailyGoal))
                    .frame(width: 120)
                Text("\(todayTotal)/\(exercise.dailyGoal)")
                    .monospacedDigit()
            }
        }
        .task(id: exercise.id) { await refreshProgress() }
        .onReceive(NotificationCenter.default.publisher(for: .repEntryUpdated)) { note in
            if let id = note.object as? UUID, id == exercise.id {
                Task { await refreshProgress() }
            }
        }
    }

    @MainActor
    private func refreshProgress() async {
        do {
            todayTotal = try DataService.todaysProgress(for: exercise, context: context)
        } catch {
            todayTotal = 0
        }
    }
}

// A tiny, type-checker-friendly view that renders S M T W T F S with active days highlighted.
struct WeekdayStripe: View {
    /// scheduled uses 1=Sun ... 7=Sat
    let scheduled: [Int]
    private let symbols: [String] = DateFormatter().veryShortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
    private let indices: [Int] = [0, 1, 2, 3, 4, 5, 6]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(indices, id: \.self) { i in
                let on = scheduled.contains(i + 1)
                Text(symbols[i])
                    .font(.caption2)
                    .fontWeight(on ? .semibold : .regular)
                    .foregroundStyle(on ? AppConfig.buttonOnTint : AppConfig.buttonDisabledTint)
            }
        }
    }
}

struct AddExerciseView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var goal: Int = 100
    // Weekday scheduling
    @State private var selectedDays: Set<Int> = Set(1...7) // default all days
    private let weekDays = Array(1...7)

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    TextField("Name (e.g., Push‑ups)", text: $name)
                }
                Section("Goal (per active day)") {
                    Stepper(value: $goal, in: 1...10000, step: 5) {
                        HStack {
                            Text("Reps per day")
                            Spacer()
                            Text("\(goal)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Schedule") {
                    HStack(spacing: 6) {
                        ForEach(weekDays, id: \.self) { d in
                            let on = selectedDays.contains(d)
                            Button(shortLabel(for: d)) {
                                if on { selectedDays.remove(d) } else { selectedDays.insert(d) }
                            }
                            .buttonStyle(BorderedButtonStyle())
                            .tint(on ? AppConfig.buttonOnTint : AppConfig.buttonDisabledTint)
                        }
                    }
                    Text("Choose the days this goal is active.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Exercise")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
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
        LocalReminderScheduler.rescheduleAll(using: context)
        dismiss()
    }

    private func shortLabel(for weekday: Int) -> String {
        let syms = DateFormatter().veryShortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        return syms[(weekday - 1 + syms.count) % syms.count]
    }
}

// MARK: - Goal Editor (quick change daily target)

struct GoalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var exercise: Exercise

    var body: some View {
        NavigationStack {
            Form {
                Section("Daily Goal") {
                    Stepper(value: $exercise.dailyGoal, in: 1...10000, step: 5) {
                        HStack {
                            Text("Reps per day")
                            Spacer()
                            Text("\(exercise.dailyGoal)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Changing the goal updates your progress bar immediately.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Daily Goal")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Save") { dismiss() } }
            }
        }
    }
}

// MARK: - Edit Exercise

struct EditExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var exercise: Exercise

    private let weekDays = Array(1...7)

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    TextField("Name", text: $exercise.name)
                }
                Section("Goal (per active day)") {
                    Stepper(value: $exercise.dailyGoal, in: 1...10000, step: 5) {
                        HStack {
                            Text("Reps per day")
                            Spacer()
                            Text("\(exercise.dailyGoal)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Schedule") {
                    HStack(spacing: 6) {
                        ForEach(weekDays, id: \.self) { d in
                            let on = exercise.scheduledWeekdays.contains(d)
                            Button(shortLabel(for: d)) {
                                var set = Set(exercise.scheduledWeekdays)
                                if on { set.remove(d) } else { set.insert(d) }
                                exercise.scheduledWeekdays = Array(set).sorted()
                            }
                            .buttonStyle(BorderedButtonStyle())
                            .tint(on ? AppConfig.buttonOnTint : AppConfig.buttonDisabledTint)
                        }
                    }
                    Text("Choose the days this goal is active.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Exercise")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Save") { LocalReminderScheduler.rescheduleAll(using: context); dismiss() } }
            }
        }
    }

    private func shortLabel(for weekday: Int) -> String {
        let syms = DateFormatter().veryShortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        return syms[(weekday - 1 + syms.count) % syms.count]
    }
}

// MARK: - Log Reps

struct LogRepsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let exercise: Exercise
    @State private var currentTotal: Int = 0
    @FocusState private var valueFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    LabeledContent("Name", value: exercise.name)
                    LabeledContent("Daily Goal", value: String(exercise.dailyGoal))
                }
                Section("Log Progress") {
                    TextField("Enter today's total", value: $currentTotal, format: .number)
                        .keyboardType(.numberPad)
                        .focused($valueFieldFocused)
                    Stepper(value: $currentTotal, in: 0...100000, step: 1) {
                        HStack {
                            Text("Current total today")
                            Spacer()
                            Text("\(currentTotal)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Button("+5") { currentTotal = min(100000, currentTotal + 5) }
                            .buttonStyle(BorderedButtonStyle())
                        Button("+10") { currentTotal = min(100000, currentTotal + 10) }
                            .buttonStyle(BorderedButtonStyle())
                        Spacer()
                        Button("Reset") { currentTotal = 0 }
                            .buttonStyle(BorderedButtonStyle())
                    }
                    Text("Tip: enter the total you've done *so far* today (not the increment). If you later do more, just log the new total.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Log Reps")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel", action: { dismiss() }) }
                ToolbarItem(placement: .topBarTrailing) { Button("Save", action: upsertSave) }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { valueFieldFocused = false } }
            }
            .onAppear { preload() }
        }
    }

    private func preload() {
        do {
            let value = try DataService.todaysProgress(for: exercise, context: context)
            currentTotal = value
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
        } catch {
            let entry = RepEntry(currentTotal: currentTotal, date: now, exercise: exercise)
            context.insert(entry)
        }
        NotificationCenter.default.post(name: .repEntryUpdated, object: exercise.id)
        LocalReminderScheduler.rescheduleAll(using: context)
        dismiss()
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsArray: [AppSettings]

    private var settings: AppSettings {
        if let s = settingsArray.first { return s }
        let s = AppSettings()
        context.insert(s)
        return s
    }

    private let hours = Array(0 ..< 24)
    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    private var modeBinding: Binding<Int> { Binding(get: { settings.modeRaw }, set: { settings.modeRaw = $0 }) }
    private var intervalBinding: Binding<Int> { Binding(get: { settings.intervalHours }, set: { settings.intervalHours = $0 }) }
    private var startHourBinding: Binding<Int> { Binding(get: { settings.startHour }, set: { settings.startHour = $0 }) }

    @ViewBuilder private var reminderModeSection: some View {
        Section("Reminder Mode") {
            Picker("Mode", selection: modeBinding) {
                Text("Every X hours").tag(0)
                Text("Specific times").tag(1)
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder private var intervalSection: some View {
        Section("Every N hours") {
            Stepper(value: intervalBinding, in: 1...12) {
                HStack {
                    Text("Interval")
                    Spacer()
                    Text("Every \(settings.intervalHours) hr")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Picker("Start hour", selection: startHourBinding) {
                ForEach(hours, id: \.self) { h in
                    Text(hourLabel(h)).tag(h)
                }
            }
        }
    }

    @ViewBuilder private var customTimesSection: some View {
        Section("Notification times") {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(hours, id: \.self) { h in
                    let isOn = settings.customHours.contains(h)
                    Button(action: { toggleHour(h) }) {
                        Text(hourLabel(h))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BorderedButtonStyle())
                    .tint(isOn ? Color.accentColor : Color.secondary)
                }
            }
            if settings.customHours.isEmpty {
                Text("Select at least one time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var applySection: some View {
        Section {
            Button("Apply & Reschedule Reminders") {
                BackgroundScheduler.rescheduleAfterSettingsChange()
                LocalReminderScheduler.rescheduleAll(using: context)
            }
        } footer: {
            Text("iOS schedules background refresh opportunistically. We reschedule to the next selected slot.")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                reminderModeSection
                if settings.mode == .interval {
                    intervalSection
                } else {
                    customTimesSection
                }
                applySection
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } } }
        }
    }

    private func toggleHour(_ h: Int) {
        var set = Set(settings.customHours)
        if set.contains(h) { set.remove(h) } else { set.insert(h) }
        settings.customHours = Array(set).sorted()
    }

    private func hourLabel(_ h: Int) -> String {
        let date = Calendar.current.date(from: DateComponents(hour: h)) ?? Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "h a"
        fmt.locale = Locale.current
        return fmt.string(from: date)
    }
}

// MARK: - Info.plist additions (add manually in your project)

//
// 1) Permitted BG task identifiers:
// <key>BGTaskSchedulerPermittedIdentifiers</key>
// <array>
//   <string>com.example.repgoal.check</string> <!-- MUST match BackgroundScheduler.taskIdentifier -->
// </array>
//
// 2) Background modes capability:
// <key>UIBackgroundModes</key>
// <array>
//   <string>fetch</string>
// </array>
//
// That's it for local notifications (no special Info.plist key needed for permission).
// ---------------------------------------------------------------------------------
