//
//  Scheduler.swift (v10)
//
import Foundation
import BackgroundTasks
import SwiftData
import UserNotifications

enum BackgroundScheduler {
    static let taskIdentifier = "com.example.repgoal.check"
    static let defaultSlots: [Int] = [7, 10, 13, 16, 19, 22]

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
        do { try BGTaskScheduler.shared.submit(request) } catch { print("⚠️ BG submit error: \(error)") }
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
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        var dc = DateComponents()
        let t = cal.dateComponents([.year, .month, .day], from: tomorrow)
        dc.year = t.year; dc.month = t.month; dc.day = t.day
        dc.hour = (loadSlots().first ?? 7); dc.minute = 0; dc.second = 0
        return cal.date(from: dc)!
    }

    static func rescheduleAfterSettingsChange() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        scheduleNextCheck()
    }

    static func loadSlots() -> [Int] {
        do {
            let config = ModelConfiguration("RepGoal")
            let container = try ModelContainer(for: Exercise.self, RepEntry.self, AppSettings.self, MacroGoal.self, configurations: config)
            let context = ModelContext(container)
            if let s = try context.fetch(FetchDescriptor<AppSettings>()).first {
                return computeSlots(from: s)
            }
        } catch { print("⚠️ loadSlots error: \(error)") }
        return defaultSlots
    }

    static func computeSlots(from s: AppSettings) -> [Int] {
        switch s.mode {
        case .interval:
            let step = max(1, min(12, s.intervalHours))
            var hours: [Int] = []
            var h = max(0, min(23, s.startHour))
            while h < 24 { hours.append(h); h += step }
            return hours
        case .custom:
            let set = Set(s.customHours.filter { (0...23).contains($0) })
            return Array(set).sorted()
        }
    }

    static func handle(task: BGAppRefreshTask) {
        scheduleNextCheck()
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        task.expirationHandler = { queue.cancelAllOperations() }
        queue.addOperation {
            do {
                let config = ModelConfiguration("RepGoal")
                let container = try ModelContainer(for: Exercise.self, RepEntry.self, AppSettings.self, MacroGoal.self, configurations: config)
                let context = ModelContext(container)
                try sendNotificationsIfNeeded(using: context)
                task.setTaskCompleted(success: true)
            } catch { print("❌ BG task failed: \(error)"); task.setTaskCompleted(success: false) }
        }
    }

    static func sendNotificationsIfNeeded(using context: ModelContext) throws {
        LocalReminderScheduler.rescheduleAll(using: context)
    }
}

enum LocalReminderScheduler {
    private static func idPrefix(for exercise: Exercise) -> String { "local.\(exercise.id.uuidString)." }
    private static func id(for exercise: Exercise, at date: Date) -> String { idPrefix(for: exercise) + String(Int(date.timeIntervalSince1970)) }

    static func rescheduleAll(using context: ModelContext, daysAhead: Int = 2) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { reqs in
            let ids = reqs.filter { $0.identifier.hasPrefix("local.") }.map { $0.identifier }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
            DispatchQueue.main.async {
                do {
                    for ex in try context.fetch(FetchDescriptor<Exercise>()) {
                        scheduleUpcoming(for: ex, using: context, daysAhead: daysAhead)
                    }
                } catch { print("⚠️ rescheduleAll fetch error: \(error)") }
            }
        }
    }

    static func scheduleUpcoming(for exercise: Exercise, using context: ModelContext, daysAhead: Int = 2, now: Date = Date()) {
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
                var comps = cal.dateComponents([.year,.month,.day], from: base)
                comps.hour = h; comps.minute = 0; comps.second = 0
                guard let candidate = cal.date(from: comps), candidate > now else { continue }
                let remaining: Int = {
                    do { return max(0, exercise.dailyGoal - (try DataService.todaysProgress(for: exercise, context: context, now: candidate))) }
                    catch { return exercise.dailyGoal }
                }()
                guard remaining > 0 else { continue }
                let content = UNMutableNotificationContent()
                content.title = exercise.name
                content.body = "You have \(remaining) reps left for today's goal."
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year,.month,.day,.hour,.minute], from: candidate), repeats: false)
                let req = UNNotificationRequest(identifier: id(for: exercise, at: candidate), content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(req)
                scheduledCount += 1
                if scheduledCount >= 16 { break outer }
            }
        }
    }
}
