import SwiftUI
import OrtusCore

struct ScheduleView: View {
    @EnvironmentObject var focusManager: FocusManager
    @State private var editingScheduleID: UUID?
    @State private var isAddingNew = false
    @Environment(\.snapshotState) private var snapshotState

    var body: some View {
        VStack(spacing: 0) {
            if focusManager.schedules.isEmpty && !isAddingNew {
                OrtusEmptyState(
                    icon: "calendar.badge.plus",
                    title: "No schedules yet",
                    message: "Choose the apps and websites to set aside during each focus window."
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
                                    onCancel: {
                                        editingScheduleID = nil
                                    },
                                    onDelete: {
                                        focusManager.deleteSchedule(schedule)
                                        editingScheduleID = nil
                                    }
                                )
                                .ortusCard()
                            } else {
                                ScheduleRow(
                                    schedule: schedule,
                                    isLocked: focusManager.activeScheduleIDs.contains(schedule.id),
                                    onEdit: {
                                        isAddingNew = false
                                        editingScheduleID = schedule.id
                                    },
                                    onToggle: { enabled in
                                        var updated = schedule
                                        updated.isEnabled = enabled
                                        focusManager.updateSchedule(updated)
                                    }
                                )
                                .ortusCard()
                            }
                        }

                        if isAddingNew {
                            ScheduleInlineEditor(
                                schedule: FocusSchedule(blocked: FocusMode.social.blocked),
                                title: "New schedule",
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

            Button {
                editingScheduleID = nil
                isAddingNew = true
            } label: {
                Label("Add schedule", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OrtusSecondaryButtonStyle())
            .disabled(isAddingNew)
            .padding(.horizontal, OrtusTheme.spacingMD)
            .padding(.bottom, OrtusTheme.spacingSM)
        }
        .onAppear { if snapshotState == "new-schedule" { isAddingNew = true } }
    }
}

// MARK: - Schedule Row

struct ScheduleRow: View {
    @EnvironmentObject var focusManager: FocusManager
    let schedule: FocusSchedule
    let isLocked: Bool
    let onEdit: () -> Void
    let onToggle: (Bool) -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: OrtusTheme.spacingMD) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(schedule.name)
                        .font(OrtusTheme.Typo.headline)
                        .foregroundStyle(.primary)

                    Text("\(daysSummary) · \(schedule.startTimeString)\u{2013}\(schedule.endTimeString)")
                        .font(OrtusTheme.Typo.body)
                        .foregroundStyle(OrtusTheme.textMuted)
                        .monospacedDigit()

                    Text((isLocked ? "Active now · " : "") + modeDescription)
                        .font(OrtusTheme.Typo.caption)
                        .foregroundStyle(isLocked ? OrtusTheme.accentInk : OrtusTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .opacity(isHovering && !isLocked ? 0.75 : 1)
            }
            .buttonStyle(.plain)
            .disabled(isLocked)
            .onHover { isHovering = $0 }
            .help(isLocked ? "Editable after this session ends" : "Edit schedule")

            Toggle("", isOn: Binding(
                get: { schedule.isEnabled },
                set: { onToggle($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(OrtusTheme.accent)
            .accessibilityLabel("\(schedule.name) enabled")
            .disabled(isLocked)
        }
    }

    /// "Social" for a known mode, else the targets.
    private var modeDescription: String {
        focusManager.mode(for: schedule.blocked)?.name ?? schedule.blocked.summary
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
    var onDelete: (() -> Void)? = nil

    @State private var startTime: Date
    @State private var endTime: Date

    init(schedule: FocusSchedule, title: String, onSave: @escaping (FocusSchedule) -> Void, onCancel: @escaping () -> Void, onDelete: (() -> Void)? = nil) {
        self._schedule = State(initialValue: schedule)
        self.title = title
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete

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

            HStack {
                DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Text("\u{2013}")
                    .foregroundStyle(OrtusTheme.textMuted)
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

            if Calendar.current.component(.hour, from: startTime) * 60 + Calendar.current.component(.minute, from: startTime) > Calendar.current.component(.hour, from: endTime) * 60 + Calendar.current.component(.minute, from: endTime) {
                Text("Ends the following day.").font(OrtusTheme.Typo.meta).foregroundStyle(OrtusTheme.textMuted)
            }

            ModePicker(selection: $schedule.blocked)

            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(OrtusGhostButtonStyle())
                if let onDelete {
                    Button(action: onDelete) {
                        Text("Delete").font(OrtusTheme.Typo.button).foregroundStyle(OrtusTheme.danger)
                    }
                    .buttonStyle(.plain)
                }

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
                .disabled(schedule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || schedule.days.isEmpty || schedule.blocked.isEmpty || Calendar.current.isDate(startTime, equalTo: endTime, toGranularity: .minute))
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
                        .fill(isSelected ? OrtusTheme.accentInk : (isHovering ? Color.primary.opacity(0.06) : .clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous)
                        .strokeBorder(isSelected ? .clear : OrtusTheme.hairline, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous))
                .foregroundStyle(isSelected ? OrtusTheme.onAccent : .primary)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.03 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
    }
}
