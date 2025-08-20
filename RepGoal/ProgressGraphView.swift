//
//  ProgressGraphView.swift (v17)
import Charts
import SwiftData
import SwiftUI

struct ProgressGraphView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let exercise: Exercise
    let palette: ThemePalette

    @State private var points: [DataService.DailyPoint] = []

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if points.isEmpty {
                    ContentUnavailableView(
                        "No Data",
                        systemImage: "chart.xyaxis.line",
                        description: Text("Log reps to see your progress.")
                    )
                } else {
                    Chart(points, id: \.id) {
                        LineMark(x: .value("Day", $0.day), y: .value("Total", $0.total))
                        PointMark(x: .value("Day", $0.day), y: .value("Total", $0.total))
                    }
                    .frame(height: 260)
                }
                Spacer()
            }
            .padding()
            .navigationTitle(exercise.name + " Progress")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    @MainActor private func load() async {
        do {
            points = try DataService.dailySeries(for: exercise, context: context, daysBack: 60)
        } catch { points = [] }
    }
}
