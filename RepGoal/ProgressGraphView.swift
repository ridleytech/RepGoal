//
//  ProgressGraphView.swift (v10)
//
import SwiftUI
import SwiftData
import Charts

struct ProgressGraphView: View {
    @Environment(\.modelContext) private var context
    let exercise: Exercise
    @State private var points: [DataService.DailyPoint] = []
    @State private var daysBack: Int = 30

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if points.isEmpty {
                    ContentUnavailableView("No Data", systemImage: "chart.bar", description: Text("Log some reps to see your progress."))
                } else {
                    Chart(points) { p in
                        LineMark(x: .value("Day", p.day), y: .value("Total", p.total))
                        PointMark(x: .value("Day", p.day), y: .value("Total", p.total))
                    }
                    .frame(height: 260)
                }
                Stepper("Days back: \(daysBack)", value: $daysBack, in: 7...180, step: 7)
                HStack {
                    Button("+5") { daysBack = min(180, daysBack + 5) }.buttonStyle(BorderedButtonStyle())
                    Button("+10") { daysBack = min(180, daysBack + 10) }.buttonStyle(BorderedButtonStyle())
                }
                .padding(.bottom, 12)
                Spacer()
            }
            .padding()
            .navigationTitle("\(exercise.name) • Progress")
            .task(id: daysBack) { await reload() }
            .task { await reload() }
        }
    }

    @MainActor
    private func reload() async {
        do { points = try DataService.dailySeries(for: exercise, context: context, daysBack: daysBack) } catch { points = [] }
    }
}
