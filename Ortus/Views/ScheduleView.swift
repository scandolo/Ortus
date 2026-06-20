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
                    title: "No schedules yet",
                    message: "Add recurring focus hours and Slack pauses itself — no thinking required."
                )
            } else {
                ScrollView {
                    VStack(spacing: OrtusTheme.spacingSM) {
                        ForEach(focusManager.schedules) { schedule in
                            if editingScheduleID == schedule.id {
                                ScheduleInlineEditor(
                                    schedule: schedule,
                                    title: "Edit schedule",
                                    onSave: { updated in
                                        focusManager.updateSchedule(updated)
                                        editingScheduleID = nil
                                    },
                                    onCancel: { editingScheduleID = nil }
                                )
                                .ortusCard(raised: true)
                                .transition(.opacity)
                            } else {
                                ScheduleRow(
                                    schedule: schedule,
                                    onEdit: {
                                        isAddingNew = false
                                        withAnimation(OrtusTheme.Motion.enter) { editingScheduleID = schedule.id }
                                    },
                                    onToggle: { enabled in
                                        var updated = schedule
                                        updated.isEnabled = enabled
                                        focusManager.updateSchedule(updated)
                                    },
                                    onDelete: { focusManager.deleteSchedule(schedule) }
                                )
                                .ortusCard()
                            }
                        }

                        if isAddingNew {
                            ScheduleInlineEditor(
                                schedule: FocusSchedule(),
                                title: "New schedule",
                                onSave: { schedule in
                                    focusManager.addSchedule(schedule)
                                    isAddingNew = false
                                },
                                onCancel: { isAddingNew = false }
                            )
                            .ortusCard(raised: true)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(OrtusTheme.spacingMD)
                    .animation(OrtusTheme.Motion.enter, value: focusManager.schedules.count)
                }
            }

            Button {
                editingScheduleID = nil
                withAnimation(OrtusTheme.Motion.enter) { isAddingNew = true }
            } label: {
                Label("Add schedule", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OrtusSecondaryButtonStyle())
            .disabled(isAddingNew)
            .padding(.horizontal, OrtusTheme.spacingMD)
            .padding(.bottom, OrtusTheme.spacingSM)
        }
    }
}

// MARK: - Schedule Row

struct ScheduleRow: View {
    let schedule: FocusSchedule
    let onEdit: () -> Void
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: OrtusTheme.spacingMD) {
            // Status rail
            Capsule()
                .fill(schedule.isEnabled ? OrtusTheme.accent : OrtusTheme.textMuted.opacity(0.4))
                .frame(width: 3, height: 38)

            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(schedule.name)
                        .font(OrtusTheme.Typo.headline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        Text(schedule.startTimeString)
                        Text("–").foregroundStyle(.tertiary)
                        Text(schedule.endTimeString)
                    }
                    .font(OrtusTheme.Typo.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                    daysPill
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(OrtusTheme.textMuted)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.primary.opacity(0.05)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Delete schedule")
                .transition(.opacity)
            }

            Toggle("", isOn: Binding(get: { schedule.isEnabled }, set: { onToggle($0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(OrtusTheme.accent)
                .accessibilityLabel("\(schedule.name) enabled")
        }
        .animation(OrtusTheme.Motion.hover, value: isHovering)
        .onHover { isHovering = $0 }
    }

    private var daysPill: some View {
        Text(daysSummary)
            .font(OrtusTheme.Typo.badge)
            .foregroundStyle(OrtusTheme.textMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(OrtusTheme.inputSurface))
            .padding(.top, 1)
    }

    private var daysSummary: String {
        let sorted = schedule.days.sorted()
        if sorted.count == 7 { return "Every day" }
        if sorted == [.monday, .tuesday, .wednesday, .thursday, .friday] { return "Weekdays" }
        if sorted == [.saturday, .sunday] { return "Weekends" }
        return sorted.map(\.shortName).joined(separator: " · ")
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
                .textFieldStyle(OrtusTextFieldStyle())

            HStack(spacing: OrtusTheme.spacingSM) {
                DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Text("–").foregroundStyle(.secondary)
                DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Spacer()
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: OrtusTheme.spacingSM), count: 7),
                      spacing: OrtusTheme.spacingSM) {
                ForEach(Weekday.allCases) { day in
                    DayToggleButton(day: day, isSelected: schedule.days.contains(day)) {
                        if schedule.days.contains(day) { schedule.days.remove(day) }
                        else { schedule.days.insert(day) }
                    }
                }
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(OrtusGhostButtonStyle())
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

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            Text(day.shortName)
                .font(OrtusTheme.Typo.badge)
                .frame(maxWidth: .infinity)
                .padding(.vertical, OrtusTheme.spacingSM)
                .background(
                    RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous)
                        .fill(isSelected ? OrtusTheme.accent : (isHovering ? Color.primary.opacity(0.06) : OrtusTheme.inputSurface))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous)
                        .strokeBorder(isSelected ? .clear : OrtusTheme.hairline, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous))
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.04 : 1.0)
        .animation(OrtusTheme.Motion.press, value: isHovering)
        .onHover { isHovering = $0 }
    }
}
