//
//  MacroFeature.swift (v10)
//
import Foundation
import SwiftUI
import SwiftData

struct FlexibleStringList: Codable {
    var items: [String] = []
    init(items: [String]) { self.items = items }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let arr = try? c.decode([String].self) { self.items = arr }
        else if let str = try? c.decode(String.self) {
            let t = str.trimmingCharacters(in: .whitespacesAndNewlines)
            let split = t.replacingOccurrences(of: "•", with: "\n")
                .replacingOccurrences(of: " - ", with: "\n")
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            self.items = split.isEmpty ? [t] : split
        } else { self.items = [] }
    }
}
struct FlexibleString: Codable {
    var string: String = ""
    init(_ s: String) { string = s }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { string = s }
        else if let i = try? c.decode(Int.self) { string = String(i) }
        else if let d = try? c.decode(Double.self) { string = (d.rounded() == d) ? String(Int(d)) : String(d) }
        else if let b = try? c.decode(Bool.self) { string = b ? "true" : "false" }
        else { string = "" }
    }
}

struct MacroPlan: Codable {
    let estimated_days: Int?
    let estimated_completion_date: String?
    let daily_recommendation: FlexibleString?
    let weekly_notes: FlexibleStringList?
    let assumptions: FlexibleStringList?
}

enum ChatGPTService {
    struct ErrorMsg: LocalizedError { let message: String; var errorDescription: String? { message } }
    static var apiBase: String = "http://localhost:6000/macro"
    static func estimatePlan(exerciseName: String, targetTotal: Int, currentMax: Int, dailyGoal: Int) async throws -> String {
        guard let url = URL(string: apiBase) else { throw ErrorMsg(message: "Invalid API base URL") }
        var req = URLRequest(url: url); req.httpMethod = "POST"; req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["exerciseName": exerciseName, "currentMax": currentMax, "targetTotal": targetTotal]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let txt = String(data: data, encoding: .utf8) ?? ""
            throw ErrorMsg(message: "API error \((resp as? HTTPURLResponse)?.statusCode ?? -1): \(txt)")
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

struct MacroPlannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let exercise: Exercise
    let palette: ThemePalette
    @State private var targetTotal: Int = 100
    @State private var currentMax: Int = 10
    @State private var isLoading: Bool = false
    @State private var resultJSON: String = ""
    @State private var plan: MacroPlan? = nil
    @State private var parseError: String? = nil
    @State private var didSave: Bool = false

    var body: some View {
        NavigationStack {
            List {
                Section("📌 Exercise") {
                    HStack { Text("Name"); Spacer(); Text(exercise.name).foregroundStyle(.secondary) }
                    HStack { Text("Daily goal"); Spacer(); Text("\(exercise.dailyGoal)").foregroundStyle(.secondary).monospacedDigit() }
                    VStack(alignment: .leading, spacing: 8) {
                        Stepper(value: $targetTotal, in: 1...100000, step: 5) { HStack { Text("🎯 Target session max"); Spacer(); Text("\(targetTotal)").foregroundStyle(.secondary).monospacedDigit() } }
                        HStack { Button("+5") { targetTotal = min(100000, targetTotal + 5) }.buttonStyle(BorderedButtonStyle()); Button("+10") { targetTotal = min(100000, targetTotal + 10) }.buttonStyle(BorderedButtonStyle()) }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Stepper(value: $currentMax, in: 0...100000, step: 1) { HStack { Text("💪 Current session max"); Spacer(); Text("\(currentMax)").foregroundStyle(.secondary).monospacedDigit() } }
                        HStack { Button("+5") { currentMax = min(100000, currentMax + 5) }.buttonStyle(BorderedButtonStyle()); Button("+10") { currentMax = min(100000, currentMax + 10) }.buttonStyle(BorderedButtonStyle()) }
                    }
                    Button { Task { await runEstimate() } } label: { HStack { if isLoading { ProgressView() }; Text(isLoading ? "Contacting API..." : "Ask ChatGPT") }.frame(maxWidth: .infinity) }.disabled(isLoading).buttonStyle(BorderedProminentButtonStyle())
                }
                if let p = plan {
                    Section("🧭 Summary") {
                        if let days = p.estimated_days { HStack { Text("📅 Estimated days"); Spacer(); Text("\(days)").monospacedDigit() } }
                        if let date = p.estimated_completion_date { HStack { Text("🗓️ Completion date"); Spacer(); Text(date).foregroundStyle(.secondary) } }
                        if let daily = p.daily_recommendation?.string, !daily.isEmpty { VStack(alignment: .leading, spacing: 6) { Text("✅ Daily recommendation"); Text(daily).foregroundStyle(.secondary) } }
                    }
                    if let weekly = p.weekly_notes?.items, !weekly.isEmpty { Section("📒 Weekly notes") { ForEach(weekly.indices, id: \.self) { i in Text(weekly[i]) } } }
                    if let assumptions = p.assumptions?.items, !assumptions.isEmpty { Section("⚙️ Assumptions") { ForEach(assumptions.indices, id: \.self) { i in Text(assumptions[i]) } } }
                    Section { Button { savePlan(p) } label: { Label(didSave ? "Saved" : "Save Plan", systemImage: didSave ? "checkmark.seal.fill" : "square.and.arrow.down").frame(maxWidth: .infinity) } .disabled(didSave) }
                }
                if let parseError { Section("Parse error") { Text(parseError).foregroundStyle(.secondary).font(.footnote) } }
                if !resultJSON.isEmpty { Section("Raw (JSON)") { Text(resultJSON).font(.system(.footnote, design: .monospaced)).textSelection(.enabled).lineLimit(10) } }
            }
            .navigationTitle("Macro Planner")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } } }
        }
    }

    private func runEstimate() async {
        isLoading = true; defer { isLoading = false }
        parseError = nil; didSave = false; plan = nil
        do {
            let jsonString = try await ChatGPTService.estimatePlan(exerciseName: exercise.name, targetTotal: targetTotal, currentMax: currentMax, dailyGoal: exercise.dailyGoal)
            resultJSON = jsonString
            if let data = jsonString.data(using: .utf8) {
                do { plan = try JSONDecoder().decode(MacroPlan.self, from: data) } catch { parseError = "Could not decode response as MacroPlan. Showing raw JSON." }
            }
        } catch { resultJSON = "{\"error\":\"\(error.localizedDescription)\"}" }
    }

    private func savePlan(_ p: MacroPlan) {
        let mg = MacroGoal(exerciseID: exercise.id, exerciseName: exercise.name, targetTotal: targetTotal, currentMax: currentMax, lastResultJSON: resultJSON, estimatedDays: p.estimated_days, completionDate: p.estimated_completion_date, dailyRecommendation: p.daily_recommendation?.string, weeklyNotes: p.weekly_notes?.items, assumptions: p.assumptions?.items)
        context.insert(mg); try? context.save(); didSave = true
    }
}

struct SavedMacrosView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\MacroGoal.createdAt, order: .reverse)]) private var macros: [MacroGoal]

    var body: some View {
        NavigationStack {
            Group {
                if macros.isEmpty { ContentUnavailableView("No Saved Plans", systemImage: "tray", description: Text("Use the Macro Planner to create and save a plan.")) }
                else {
                    List {
                        ForEach(macros) { m in
                            NavigationLink { MacroDetailView(macro: m) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(m.exerciseName).font(.headline)
                                    HStack {
                                        if let days = m.estimatedDays { Text("📅 \(days) days").foregroundStyle(.secondary) }
                                        if let date = m.completionDate, !date.isEmpty { Text("• 🗓️ \(date)").foregroundStyle(.secondary) }
                                    }.font(.caption)
                                }
                            }
                            .listRowBackground(Color.clear)
                        }
                        .onDelete { idx in for i in idx { context.delete(macros[i]) }; try? context.save() }
                    }.listStyle(.plain)
                }
            }
            .navigationTitle("Saved Plans").toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } } }
        }
    }
}

struct MacroDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var macro: MacroGoal

    var body: some View {
        List {
            Section("📌 Exercise") {
                HStack { Text("Name"); Spacer(); Text(macro.exerciseName).foregroundStyle(.secondary) }
                HStack { Text("🎯 Target total"); Spacer(); Text("\(macro.targetTotal)").foregroundStyle(.secondary).monospacedDigit() }
                HStack { Text("💪 Current max"); Spacer(); Text("\(macro.currentMax)").foregroundStyle(.secondary).monospacedDigit() }
                HStack { Text("Saved"); Spacer(); Text(macro.createdAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary) }
            }
            Section("🧭 Summary") {
                if let days = macro.estimatedDays { HStack { Text("📅 Estimated days"); Spacer(); Text("\(days)").monospacedDigit() } }
                if let date = macro.completionDate, !date.isEmpty { HStack { Text("🗓️ Completion date"); Spacer(); Text(date).foregroundStyle(.secondary) } }
                if let daily = macro.dailyRecommendation, !daily.isEmpty { VStack(alignment: .leading, spacing: 6) { Text("✅ Daily recommendation"); Text(daily).foregroundStyle(.secondary) } }
            }
            if let weekly = macro.weeklyNotes, !weekly.isEmpty { Section("📒 Weekly notes") { ForEach(weekly.indices, id: \.self) { i in Text(weekly[i]) } } }
            if let assumptions = macro.assumptions, !assumptions.isEmpty { Section("⚙️ Assumptions") { ForEach(assumptions.indices, id: \.self) { i in Text(assumptions[i]) } } }
            if !macro.lastResultJSON.isEmpty { Section("Raw (JSON)") { Text(macro.lastResultJSON).font(.system(.footnote, design: .monospaced)).textSelection(.enabled).lineLimit(10) } }
        }
        .navigationTitle("Plan Details")
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } } }
    }
}
