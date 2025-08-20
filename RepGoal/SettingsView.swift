import SwiftData
import SwiftUI

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

    private var palette: ThemePalette { ThemeKit.palette(settings) }
    private var isDark: Bool { ThemeKit.isDark(settings) }

    // MARK: - Sections

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
            VStack(alignment: .leading, spacing: 8) {
                Stepper(value: intervalBinding, in: 1 ... 12) {
                    HStack {
                        Text("Interval")
                        Spacer()
                        Text("Every \(settings.intervalHours) hr")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                // Quick increments
                HStack {
                    Button("+1") { settings.intervalHours = min(12, settings.intervalHours + 1) }
                        .buttonStyle(BorderedButtonStyle())
                    Button("+2") { settings.intervalHours = min(12, settings.intervalHours + 2) }
                        .buttonStyle(BorderedButtonStyle())
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
                    .tint(isOn ? palette.onTint : palette.offTint)
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
            Button {
                BackgroundScheduler.rescheduleAfterSettingsChange()
                LocalReminderScheduler.rescheduleAll(using: context)
            } label: {
                HStack {
                    Spacer()
                    Text("Apply & Reschedule Reminders")
                    Spacer()
                }
            }
            .buttonStyle(ThemedProminentButtonStyle(palette: palette)) // filled + press feedback
        } footer: {
            Text("iOS schedules background refresh opportunistically. We reschedule to the next selected slot.")
        }
    }

    @ViewBuilder private var themeSection: some View {
        Section("Theme") {
            ForEach(ThemeOption.allCases) { opt in
                Button {
                    settings.themeRaw = opt.rawValue
                } label: {
                    // Align all content by the row's vertical center (no alignmentGuides needed)
                    HStack(alignment: .center, spacing: 12) {
                        Text(opt.name)

                        Spacer(minLength: 8)

                        // Swatches centered vertically via fixed height and maxHeight centering
                        SwatchRow(colors: opt.swatch)
                            .frame(height: 22)
                            .frame(maxHeight: .infinity, alignment: .center)

                        // Checkmark pinned far-right with fixed width to avoid overlay/shift
                        Group {
                            if settings.themeRaw == opt.rawValue {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(opt.palette.onTint)
                            } else {
                                Image(systemName: "circle").opacity(0)
                            }
                        }
                        .frame(width: 22, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                }
                // Keep text visible across themes; row background is transparent so parent theming shows through
                .tint(ThemeKit.palette(settings).text)
                .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: - Body

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
                themeSection
            }
            .themed(palette: palette, isDark: isDark) // ensure background/text adapt here too
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - Helpers

    private func toggleHour(_ h: Int) {
        var set = Set(settings.customHours)
        if set.contains(h) { set.remove(h) } else { set.insert(h) }
        settings.customHours = Array(set).sorted()
    }

    private func hourLabel(_ h: Int) -> String {
        let date = Calendar.current.date(from: DateComponents(hour: h)) ?? Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "h a"
        fmt.locale = .current
        return fmt.string(from: date)
    }
}

// MARK: - SwatchRow helper

struct SwatchRow: View {
    let colors: [Color]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(colors.enumerated()), id: \.0) { _, c in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(c)
                    .frame(width: 18, height: 18)
            }
        }
        .frame(height: 22) // stable height so it centers nicely in the row
        .padding(.vertical, 2)
    }
}

// MARK: - Local filled button style with press feedback (in case it's not defined elsewhere)

struct ThemedProminentButtonStyle: ButtonStyle {
    let palette: ThemePalette
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(palette.onTint)
            .foregroundStyle(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
