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
                    message: "Choose the apps and websites to set aside during each focus window."
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
        .onAppear { if snapshotState == "new-schedule" || snapshotState == "schedule-modes" { isAddingNew = true } }
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
                        Text(isLocked ? "Active until \(activeEndTimeString) · \(modeDescription)" : modeDescription)
                    }
                    .font(OrtusTheme.Typo.caption)
                    .foregroundStyle(OrtusTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                // Off reads as off: the text fades, the toggle stays at full strength.
                .opacity(schedule.isEnabled || isLocked ? 1 : 0.5)
                .animation(.easeOut(duration: 0.25), value: schedule.isEnabled)
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
                .accessibilityLabel("Name")

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
                // Delete stands apart on the left, away from Cancel and Save.
                if let onDelete {
                    Button("Delete", action: onDelete)
                        .buttonStyle(OrtusGhostButtonStyle(size: .medium))
                }

                Spacer()

                Button("Cancel", action: onCancel)
                    .buttonStyle(OrtusGhostButtonStyle(size: .medium))

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
/// 15 minutes. The number is a field: type "9:30", "2130" or "9pm". What's on screen is
/// always what gets saved, even without pressing Return. Return, Esc or a click
/// anywhere else in the panel ends typing.
struct TimeStepper: View {
    @Binding var time: Date
    let label: String
    @State private var text = ""
    /// The time when typing started, for Esc.
    @State private var timeBeforeTyping: Date?
    @State private var clickMonitor: Any?
    @FocusState private var focused: Bool
    @Environment(\.ortusOnCard) private var onCard

    private var minutes: Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func set(_ total: Int) {
        let wrapped = ((total % 1440) + 1440) % 1440
        time = Calendar.current.date(bySettingHour: wrapped / 60, minute: wrapped % 60, second: 0, of: time) ?? time
    }

    /// One 15-minute step, landing on the quarter hour.
    private func step(_ direction: Int) {
        set(direction > 0 ? (minutes / 15 + 1) * 15 : (minutes % 15 == 0 ? minutes - 15 : minutes / 15 * 15))
        text = label24
    }

    private var label24: String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    var body: some View {
        HStack(spacing: 8) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(OrtusFont.text(17, .bold)).monospacedDigit()
                .frame(width: 56)
                .focused($focused)
                .onAppear { text = label24 }
                .onChange(of: text) { _, new in if let parsed = Self.parse(new) { set(parsed) } }
                .onChange(of: minutes) { _, _ in if !focused { text = label24 } }
                // Tidy "930" into "09:30", or put back the time if what was typed can't be read.
                .onChange(of: focused) { _, isFocused in
                    if isFocused { timeBeforeTyping = time } else { text = label24 }
                    endTypingOnClickElsewhere(isFocused)
                }
                .onDisappear { endTypingOnClickElsewhere(false) }
                .onSubmit { text = label24; focused = false }
                .onExitCommand {
                    if let timeBeforeTyping { time = timeBeforeTyping }
                    text = label24
                    focused = false
                }
                .onKeyPress(.upArrow) { step(1); return .handled }
                .onKeyPress(.downArrow) { step(-1); return .handled }
                .help("Type a time, like 9:30 or 21:00")
                .accessibilityLabel("\(label) time")
                .accessibilityValue(label24)
                .accessibilityAdjustableAction { direction in step(direction == .increment ? 1 : -1) }
            VStack(spacing: 0) {
                Button { step(1) } label: {
                    OrtusIcon(.chevronDown, size: 10).rotationEffect(.degrees(180)).frame(width: 22, height: 15).contentShape(Rectangle())
                }
                .accessibilityLabel("\(label) 15 minutes later")
                Button { step(-1) } label: {
                    OrtusIcon(.chevronDown, size: 10).frame(width: 22, height: 15).contentShape(Rectangle())
                }
                .accessibilityLabel("\(label) 15 minutes earlier")
            }
            .buttonStyle(OrtusPressableStyle(cornerRadius: 5))
            .foregroundStyle(OrtusTheme.textMuted)
        }
        .padding(.leading, 14).padding(.trailing, 8)
        .frame(height: OrtusTheme.controlHeight)
        .background(RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous).fill(OrtusTheme.controlFill(onCard: onCard)))
        .overlay {
            if focused { RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous).strokeBorder(OrtusTheme.text, lineWidth: 2) }
        }
        .animation(.easeOut(duration: 0.15), value: focused)
    }

    /// While typing, a click anywhere in the panel outside the field ends it, arrows
    /// included (they still step). AppKit only does that for clicks on other fields.
    private func endTypingOnClickElsewhere(_ watch: Bool) {
        if !watch, let clickMonitor { NSEvent.removeMonitor(clickMonitor); self.clickMonitor = nil }
        guard watch, clickMonitor == nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            MainActor.assumeIsolated {
                // While typing, the first responder is the field editor; its delegate is the field.
                if let window = event.window, let field = (window.firstResponder as? NSText)?.delegate as? NSView,
                   window.contentView?.superview?.hitTest(event.locationInWindow)?.isDescendant(of: field) != true {
                    window.makeFirstResponder(nil)
                }
            }
            return event
        }
    }

    /// Minutes after midnight for "9", "930", "9:30", "09.30", "21:00", "9pm", "9:30 am".
    /// Nil when it isn't a time (yet), including a half-typed "21:3".
    static func parse(_ raw: String) -> Int? {
        let lower = raw.lowercased()
        let pm = lower.contains("p"), am = lower.contains("a")
        let parts = lower.split(whereSeparator: { !$0.isNumber }).map(String.init)
        var hour: Int?, minute = 0
        if parts.count >= 2 {
            guard parts[1].count == 2 else { return nil }
            hour = Int(parts[0]); minute = Int(parts[1]) ?? -1
        } else if let digits = parts.first {
            if digits.count <= 2 { hour = Int(digits) }
            else if digits.count <= 4 { hour = Int(digits.dropLast(2)); minute = Int(digits.suffix(2)) ?? -1 }
        }
        guard var h = hour, (0..<60).contains(minute) else { return nil }
        if am || pm {
            guard (1...12).contains(h) else { return nil }
            h = h % 12 + (pm ? 12 : 0)
        }
        guard (0..<24).contains(h) else { return nil }
        return h * 60 + minute
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
        .buttonStyle(OrtusPressableStyle(cornerRadius: 10))
        .accessibilityLabel(day.shortName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
