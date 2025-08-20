//
//  DataService.swift (v13)
import Foundation
import SwiftData

extension Calendar {
    func dayBounds(for date: Date) -> (start: Date, end: Date) {
        let start = startOfDay(for: date)
        let end = self.date(byAdding: .day, value: 1, to: start)!
        return (start, end)
    }
}

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

    struct DailyPoint: Identifiable { let id = UUID(); let day: Date; let total: Int }

    static func dailySeries(for exercise: Exercise, context: ModelContext, daysBack: Int = 30, now: Date = Date()) throws -> [DailyPoint] {
        let cal = Calendar.current
        let windowStart = cal.date(byAdding: .day, value: -daysBack, to: cal.startOfDay(for: now))!
        let exID = exercise.id
        let predicate = #Predicate<RepEntry> { entry in
            entry.exercise?.id == exID && entry.date >= windowStart && entry.date < now
        }
        let desc = FetchDescriptor<RepEntry>(predicate: predicate, sortBy: [SortDescriptor(\RepEntry.date, order: .forward)])
        let entries = try context.fetch(desc)
        let grouped = Dictionary(grouping: entries) { e in Calendar.current.startOfDay(for: e.date) }
        let points: [DailyPoint] = grouped.map { (day, items) in DailyPoint(day: day, total: items.map { $0.currentTotal }.max() ?? 0) }
        return points.sorted { $0.day < $1.day }
    }
}

extension Notification.Name { static let repEntryUpdated = Notification.Name("RepEntryUpdated") }
