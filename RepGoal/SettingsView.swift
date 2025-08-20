//
//  SettingsView.swift (v10)
//
import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsArray: [AppSettings]

    private var settings: AppSettings {
        if let s = settingsArray.first { return s }
        let s = AppSettings(); context.insert(s); return s
    }

    private let hours = Array(0 ..< 24)
    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    private var modeBinding: Binding<Int> { Binding(get: { settings.modeRaw }, set: { settings.modeRaw = $0 }) }
    private var intervalBinding: Binding<Int> { Binding(get: { settings.intervalHours }, set: { settings.intervalHours = $0 }) }
    private var startHourBinding: Binding<Int> { Binding(get: { settings.startHour }, set: { settings.startHour = $0 }) }

    var body: some View {
        let livePalette = ThemeKit.palette(settings)
        let isDark = ThemeKit.isDark(settings)
        return NavigationStack {
            Form {
                // Notifications first
                Section("Reminder Mode") {
                    Picker("Mode", selection: modeBinding) {
                        Text("Every X hours").tag(0)
                        Text("Specific times").tag(1)
                    }.pickerStyle(.segmented)
                }.listRowBackground(Color.clear)

                if settings.mode == .interval {
                    Section("Every N hours") {
                        Stepper(value: intervalBinding, in: 1 ... 12) {
                            HStack { Text("Interval"); Spacer(); Text("Every \(settings.intervalHours) hr").monospacedDigit().foregroundStyle(.secondary) }
                        }
                        Picker("Start hour", selection: startHourBinding) {
                            ForEach(hours, id: \.self) { h in Text(hourLabel(h)).tag(h) }
                        }
                    }.listRowBackground(Color.clear)
                } else {
                    Section("Notification times") {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(hours, id: \.self) { h in
                                let isOn = settings.customHours.contains(h)
                                Button(action: { toggleHour(h) }) { Text(hourLabel(h)).frame(maxWidth: .infinity) }
                                    .buttonStyle(BorderedButtonStyle())
                                    .tint(isOn ? livePalette.onTint : livePalette.offTint)
                            }
                        }
                        if settings.customHours.isEmpty {
                            Text("Select at least one time.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }.listRowBackground(Color.clear)
                }

                Section {
                    Button("Apply & Reschedule Reminders") {
                        BackgroundScheduler.rescheduleAfterSettingsChange()
                        LocalReminderScheduler.rescheduleAll(using: context)
                    }
                } footer: {
                    Text("We schedule local notifications for upcoming time slots.")
                }.listRowBackground(Color.clear)

                // Theme section BELOW notifications
                Section("Theme") {
                    ForEach(ThemeOption.allCases) { opt in
                        HStack(spacing: 12) {
                            Text(opt.name)
                            Spacer()
                            HStack(spacing: 4) {
                                ForEach(opt.swatch.indices, id: \.self) { i in
                                    RoundedRectangle(cornerRadius: 3).fill(opt.swatch[i]).frame(width: 18, height: 12)
                                }
                            }
                            Spacer(minLength: 12)
                            if settings.themeRaw == opt.rawValue {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { settings.themeRaw = opt.rawValue; try? context.save() }
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } } }
            .themed(palette: livePalette, isDark: isDark)
        }
    }

    private func toggleHour(_ h: Int) {
        var set = Set(settings.customHours)
        if set.contains(h) { set.remove(h) } else { set.insert(h) }
        settings.customHours = Array(set).sorted()
        try? context.save()
    }

    private func hourLabel(_ h: Int) -> String {
        let date = Calendar.current.date(from: DateComponents(hour: h)) ?? Date()
        let fmt = DateFormatter(); fmt.dateFormat = "h a"; fmt.locale = .current
        return fmt.string(from: date)
    }
}
