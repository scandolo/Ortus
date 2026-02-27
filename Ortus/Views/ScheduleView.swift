import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject var focusManager: FocusManager
    @State private var editingScheduleID: UUID?
    @State private var isAddingNew = false

    var body: some View {
        VStack(spacing: 0) {
            if focusManager.schedules.isEmpty && !isAddingNew {
                OrtusEmptyState(
                    icon: "calendar.badge.plus",
                    title: "No Schedules",
                    message: "Add a schedule to automatically block Slack during focus hours."
                )
            } else {
                ScrollView {
                    VStack(spacing: OrtusTheme.spacingSM) {
                        ForEach(focusManager.schedules) { schedule in
                            if editingScheduleID == schedule.id {
                                ScheduleInlineEditor(
                                    schedule: schedule,
                                    title: "Edit Schedule",
                                    onSave: { updated in
                                        focusManager.updateSchedule(updated)
                                        editingScheduleID = nil
                                    },
                                    onCancel: {
                                        editingScheduleID = nil
                                    }
                                )
                                .ortusCard()
                            } else {
                                ScheduleRow(
                                    schedule: schedule,
                                    onEdit: {
                                        isAddingNew = false
                                        editingScheduleID = schedule.id
                                    },
                                    onToggle: { enabled in
                                        var updated = schedule
                                        updated.isEnabled = enabled
                                        focusManager.updateSchedule(updated)
                                    },
                                    onDelete: {
                                        focusManager.deleteSchedule(schedule)
                                    }
                                )
                                .ortusCard()
                            }
                        }

                        if isAddingNew {
                            ScheduleInlineEditor(
                                schedule: FocusSchedule(),
                                title: "New Schedule",
                                onSave: { schedule in
                                    focusManager.addSchedule(schedule)
                                    isAddingNew = false
                                },
                                onCancel: {
                                    isAddingNew = false
                                }
                            )
                            .ortusCard()
                        }
                    }
                    .padding(OrtusTheme.spacingMD)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button {
                    editingScheduleID = nil
                    isAddingNew = true
                } label: {
                    Label("Add Schedule", systemImage: "plus")
                }
                .disabled(isAddingNew)
                .padding(OrtusTheme.spacingMD)
            }
        }
    }
}

// MARK: - Schedule Row

struct ScheduleRow: View {
    let schedule: FocusSchedule
    let onEdit: () -> Void
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: OrtusTheme.spacingXS) {
                    Text(schedule.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(daysSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(schedule.startTimeString) \u{2013} \(schedule.endTimeString)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete schedule")

            Toggle("", isOn: Binding(
                get: { schedule.isEnabled },
                set: { onToggle($0) }
            ))
            .labelsHidden()
        }
    }

    private var daysSummary: String {
        let sorted = schedule.days.sorted()
        if sorted.count == 7 { return "Every day" }
        if sorted == [.monday, .tuesday, .wednesday, .thursday, .friday] { return "Weekdays" }
        if sorted == [.saturday, .sunday] { return "Weekends" }
        return sorted.map(\.shortName).joined(separator: ", ")
    }
}

// MARK: - Inline Schedule Editor

struct ScheduleInlineEditor: View {
    @State var schedule: FocusSchedule
    let title: String
    let onSave: (FocusSchedule) -> Void
    let onCancel: () -> Void

    @State private var startTime: Date
    @State private var endTime: Date

    init(schedule: FocusSchedule, title: String, onSave: @escaping (FocusSchedule) -> Void, onCancel: @escaping () -> Void) {
        self._schedule = State(initialValue: schedule)
        self.title = title
        self.onSave = onSave
        self.onCancel = onCancel

        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: schedule.startHour, minute: schedule.startMinute, second: 0, of: Date()) ?? Date()
        let end = calendar.date(bySettingHour: schedule.endHour, minute: schedule.endMinute, second: 0, of: Date()) ?? Date()
        self._startTime = State(initialValue: start)
        self._endTime = State(initialValue: end)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OrtusTheme.spacingMD) {
            OrtusSectionHeader(title: title)

            TextField("Name", text: $schedule.name)
                .textFieldStyle(.roundedBorder)

            HStack {
                DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Text("\u{2013}")
                    .foregroundStyle(.secondary)
                DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: OrtusTheme.spacingSM) {
                ForEach(Weekday.allCases) { day in
                    DayToggleButton(day: day, isSelected: schedule.days.contains(day)) {
                        if schedule.days.contains(day) {
                            schedule.days.remove(day)
                        } else {
                            schedule.days.insert(day)
                        }
                    }
                }
            }

            HStack {
                Button("Cancel", action: onCancel)

                Spacer()

                Button("Save") {
                    let calendar = Calendar.current
                    schedule.startHour = calendar.component(.hour, from: startTime)
                    schedule.startMinute = calendar.component(.minute, from: startTime)
                    schedule.endHour = calendar.component(.hour, from: endTime)
                    schedule.endMinute = calendar.component(.minute, from: endTime)
                    onSave(schedule)
                }
                .buttonStyle(OrtusPrimaryButtonStyle())
                .disabled(schedule.name.isEmpty || schedule.days.isEmpty)
            }
        }
    }
}

// MARK: - Day Toggle Button

struct DayToggleButton: View {
    let day: Weekday
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(day.shortName)
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? OrtusTheme.primary : Color.clear)
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
