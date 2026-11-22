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
                    icon: .schedule,
                    title: "No schedules yet",
                    message: "A schedule locks you in at the same time each day, with no way to skip it."
                )
            } else {
                ScrollView {
                    VStack(spacing: 10) {
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
                .scrollIndicators(.never)
            }

            Button {
                editingScheduleID = nil
                isAddingNew = true
            } label: {
                HStack(spacing: 8) {
                    OrtusIcon(.plus, size: 14)
                    Text("Add schedule")
                }
            }
            .buttonStyle(OrtusSecondaryButtonStyle(fullWidth: true))
            .disabled(isAddingNew)
            .padding([.horizontal, .bottom], OrtusTheme.spacingMD)
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
        HStack(spacing: 12) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(schedule.name)
                        .font(OrtusTheme.Typo.cardTitle)
                        .foregroundStyle(OrtusTheme.text)

                    Text("\(daysSummary) · \(schedule.startTimeString)\u{2013}\(schedule.endTimeString)")
                        .font(OrtusFont.text(14))
                        .foregroundStyle(OrtusTheme.textMuted)
                        .monospacedDigit()

                    HStack(spacing: 6) {
                        OrtusIcon(isLocked ? .locked : .blocked, size: 12)
                            .foregroundStyle(isLocked ? OrtusTheme.accent : OrtusTheme.textMuted)
                        Text(isLocked ? "Locked until \(activeEndTimeString) · \(modeDescription)" : modeDescription)
                    }
                    .font(OrtusTheme.Typo.caption)
                    .foregroundStyle(OrtusTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .opacity(isHovering && !isLocked ? 0.75 : 1)
            }
            .buttonStyle(OrtusPressableStyle(highlight: false))
            .disabled(isLocked)
            .onHover { isHovering = $0 }
            .help(isLocked ? "Editable after this session ends" : "Edit schedule")

            Toggle("", isOn: Binding(
                get: { schedule.isEnabled },
                set: { onToggle($0) }
            ))
            .labelsHidden()
            .toggleStyle(OrtusToggleStyle())
            .accessibilityLabel("\(schedule.name) enabled")
            .disabled(isLocked)
        }
    }

    private var activeEndTimeString: String {
        guard let end = focusManager.activeScheduleEndTime(for: schedule.id) else { return schedule.endTimeString }
        let time = Calendar.current.dateComponents([.hour, .minute], from: end)
        return String(format: "%d:%02d", time.hour ?? schedule.endHour, time.minute ?? schedule.endMinute)
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
        VStack(alignment: .leading, spacing: 14) {
            OrtusSectionHeader(title: title)

            TextField("", text: $schedule.name, prompt: Text("Name").foregroundStyle(OrtusTheme.textMuted))
                .textFieldStyle(OrtusTextFieldStyle())

            HStack(spacing: 10) {
                TimeStepper(time: $startTime, label: "Start")
                Text("to").font(OrtusTheme.Typo.body).foregroundStyle(OrtusTheme.textMuted)
                TimeStepper(time: $endTime, label: "End")
            }

            HStack(spacing: 5) {
                ForEach([Weekday.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]) { day in
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

            HStack(spacing: 4) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(OrtusGhostButtonStyle(size: .medium))
                if let onDelete {
                    Button("Delete", action: onDelete)
                        .buttonStyle(OrtusGhostButtonStyle(size: .medium))
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

// MARK: - Time stepper

/// A time of day as one big number on sand, with up and down arrows that move it by
/// 15 minutes. Click the number to type a time.
struct TimeStepper: View {
    @Binding var time: Date
    let label: String
    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    private var minutes: Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func set(_ total: Int) {
        let wrapped = ((total % 1440) + 1440) % 1440
        time = Calendar.current.date(bySettingHour: wrapped / 60, minute: wrapped % 60, second: 0, of: time) ?? time
    }

    private var label24: String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    var body: some View {
        HStack(spacing: 10) {
            if isEditing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(OrtusFont.text(17, .bold)).monospacedDigit()
                    .frame(width: 52)
                    .focused($fieldFocused)
                    .onSubmit(commit)
                    .onChange(of: fieldFocused) { _, focused in if !focused { commit() } }
            } else {
                Text(label24)
                    .font(OrtusFont.text(17, .bold)).monospacedDigit()
                    .frame(width: 52, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { draft = label24; isEditing = true; fieldFocused = true }
            }
            VStack(spacing: 2) {
                Button { set((minutes / 15 + 1) * 15) } label: {
                    OrtusIcon(.chevronDown, size: 10).rotationEffect(.degrees(180)).frame(width: 16, height: 12).contentShape(Rectangle())
                }
                .accessibilityLabel("Later")
                Button { set(minutes % 15 == 0 ? minutes - 15 : minutes / 15 * 15) } label: {
                    OrtusIcon(.chevronDown, size: 10).frame(width: 16, height: 12).contentShape(Rectangle())
                }
                .accessibilityLabel("Earlier")
            }
            .buttonStyle(OrtusPressableStyle(cornerRadius: 4, highlight: false))
            .foregroundStyle(OrtusTheme.textMuted)
        }
        .padding(.horizontal, 14)
        .frame(height: OrtusTheme.controlHeight)
        .background(RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous).fill(OrtusTheme.fill))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(label) time, \(label24)")
    }

    /// Accepts "9", "930", "9:30", "09.30".
    private func commit() {
        guard isEditing else { return }
        isEditing = false
        let digits = draft.filter(\.isNumber)
        let parts = draft.split(whereSeparator: { ":.h ".contains($0) }).map(String.init)
        var hour: Int?, minute = 0
        if parts.count >= 2 { hour = Int(parts[0]); minute = Int(parts[1]) ?? 0 }
        else if digits.count <= 2 { hour = Int(digits) }
        else if digits.count <= 4 { hour = Int(digits.dropLast(2)); minute = Int(digits.suffix(2)) ?? 0 }
        guard let hour, (0..<24).contains(hour), (0..<60).contains(minute) else { return }
        set(hour * 60 + minute)
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
                .font(OrtusFont.text(13, .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? OrtusTheme.strong : OrtusTheme.fill)
                )
                .foregroundStyle(isSelected ? OrtusTheme.onStrong : OrtusTheme.text)
                .contentShape(Rectangle())
        }
        .buttonStyle(OrtusPressableStyle(cornerRadius: 10, highlight: false))
        .accessibilityLabel(day.shortName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
