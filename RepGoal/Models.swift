//
//  Models.swift (v10)
//
import Foundation
import SwiftData

@Model final class Exercise: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var dailyGoal: Int
    var createdAt: Date
    /// Active weekdays (1=Sun ... 7=Sat)
    var scheduledWeekdays: [Int]
    @Relationship(deleteRule: .cascade, inverse: \RepEntry.exercise)
    var entries: [RepEntry] = []

    init(name: String, dailyGoal: Int, scheduledWeekdays: [Int] = Array(1...7), id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id; self.name = name; self.dailyGoal = dailyGoal; self.scheduledWeekdays = scheduledWeekdays; self.createdAt = createdAt
    }
    func isScheduled(on date: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return scheduledWeekdays.contains(weekday)
    }
}

@Model final class RepEntry: Identifiable {
    @Attribute(.unique) var id: UUID
    var date: Date
    var currentTotal: Int
    var exercise: Exercise?
    init(currentTotal: Int, date: Date = Date(), exercise: Exercise?, id: UUID = UUID()) {
        self.id = id; self.currentTotal = currentTotal; self.date = date; self.exercise = exercise
    }
}

@Model final class AppSettings {
    @Attribute(.unique) var id: UUID
    var modeRaw: Int
    var startHour: Int
    var intervalHours: Int
    var customHours: [Int]
    var createdAt: Date
    var themeRaw: Int
    init(id: UUID = UUID(), modeRaw: Int = 0, startHour: Int = 7, intervalHours: Int = 3, customHours: [Int] = [7,10,13,16,19,22], createdAt: Date = Date(), themeRaw: Int = 0) {
        self.id = id; self.modeRaw = modeRaw; self.startHour = startHour; self.intervalHours = intervalHours; self.customHours = customHours; self.createdAt = createdAt; self.themeRaw = themeRaw
    }
    enum Mode: Int { case interval = 0, custom = 1 }
    var mode: Mode {
        get { Mode(rawValue: modeRaw) ?? .interval }
        set { modeRaw = newValue.rawValue }
    }
}

@Model final class MacroGoal: Identifiable {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var exerciseID: UUID
    var exerciseName: String
    var targetTotal: Int
    var currentMax: Int
    var lastResultJSON: String
    var estimatedDays: Int?
    var completionDate: String?
    var dailyRecommendation: String?
    var weeklyNotes: [String]?
    var assumptions: [String]?
    init(exerciseID: UUID, exerciseName: String, targetTotal: Int, currentMax: Int, lastResultJSON: String, estimatedDays: Int? = nil, completionDate: String? = nil, dailyRecommendation: String? = nil, weeklyNotes: [String]? = nil, assumptions: [String]? = nil, id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id; self.createdAt = createdAt; self.exerciseID = exerciseID; self.exerciseName = exerciseName; self.targetTotal = targetTotal; self.currentMax = currentMax; self.lastResultJSON = lastResultJSON; self.estimatedDays = estimatedDays; self.completionDate = completionDate; self.dailyRecommendation = dailyRecommendation; self.weeklyNotes = weeklyNotes; self.assumptions = assumptions
    }
}
