import Foundation

/// Curated map of Slack `:shortcode:` → Unicode glyph for the in-app emoji picker.
///
/// Slack's `users.profile.set` API stores the emoji as a `:shortcode:` string, so the
/// app always persists shortcodes. The catalog only exists so the picker and preview
/// can render the actual glyph. Custom workspace emoji (`:my-company-logo:`) aren't in
/// here by design — for those, the picker exposes a "custom code" fallback that just
/// stores the raw shortcode and shows `:code:` in the preview.
enum EmojiCatalog {
    struct Entry: Hashable {
        let code: String   // e.g. ":no_entry_sign:"
        let glyph: String  // e.g. "🚫"
        let keywords: String // space-separated, lowercase, for fuzzy search
    }

    struct Section: Hashable {
        let title: String
        let entries: [Entry]
    }

    static let sections: [Section] = [
        Section(title: "Focus", entries: [
            Entry(code: ":no_entry_sign:", glyph: "🚫", keywords: "no entry sign block stop dnd focus"),
            Entry(code: ":no_entry:", glyph: "⛔", keywords: "no entry stop"),
            Entry(code: ":no_bell:", glyph: "🔕", keywords: "no bell mute silent quiet"),
            Entry(code: ":mute:", glyph: "🔇", keywords: "mute silent quiet"),
            Entry(code: ":shushing_face:", glyph: "🤫", keywords: "shush quiet shh"),
            Entry(code: ":speak_no_evil:", glyph: "🙊", keywords: "monkey speak quiet"),
            Entry(code: ":see_no_evil:", glyph: "🙈", keywords: "monkey see"),
            Entry(code: ":construction:", glyph: "🚧", keywords: "construction work busy"),
            Entry(code: ":zipper_mouth_face:", glyph: "🤐", keywords: "zipper quiet silent"),
        ]),
        Section(title: "Working", entries: [
            Entry(code: ":brain:", glyph: "🧠", keywords: "brain thinking deep work"),
            Entry(code: ":computer:", glyph: "💻", keywords: "computer laptop coding work"),
            Entry(code: ":keyboard:", glyph: "⌨️", keywords: "keyboard typing"),
            Entry(code: ":desktop_computer:", glyph: "🖥️", keywords: "desktop monitor"),
            Entry(code: ":writing_hand:", glyph: "✍️", keywords: "writing pen"),
            Entry(code: ":memo:", glyph: "📝", keywords: "memo notes writing"),
            Entry(code: ":pencil2:", glyph: "✏️", keywords: "pencil writing"),
            Entry(code: ":books:", glyph: "📚", keywords: "books reading learning"),
            Entry(code: ":bulb:", glyph: "💡", keywords: "idea bulb light"),
            Entry(code: ":dart:", glyph: "🎯", keywords: "dart target goal"),
            Entry(code: ":rocket:", glyph: "🚀", keywords: "rocket ship launch shipping"),
            Entry(code: ":hammer_and_wrench:", glyph: "🛠️", keywords: "tools building"),
            Entry(code: ":gear:", glyph: "⚙️", keywords: "gear settings"),
            Entry(code: ":mag:", glyph: "🔍", keywords: "magnifying glass search research"),
        ]),
        Section(title: "Time", entries: [
            Entry(code: ":tomato:", glyph: "🍅", keywords: "tomato pomodoro timer"),
            Entry(code: ":alarm_clock:", glyph: "⏰", keywords: "alarm clock time"),
            Entry(code: ":stopwatch:", glyph: "⏱️", keywords: "stopwatch timer"),
            Entry(code: ":timer_clock:", glyph: "⏲️", keywords: "timer"),
            Entry(code: ":hourglass_flowing_sand:", glyph: "⏳", keywords: "hourglass time waiting"),
            Entry(code: ":hourglass:", glyph: "⌛", keywords: "hourglass time"),
            Entry(code: ":calendar:", glyph: "📅", keywords: "calendar date schedule"),
            Entry(code: ":spiral_calendar_pad:", glyph: "🗓️", keywords: "calendar schedule"),
            Entry(code: ":clock3:", glyph: "🕒", keywords: "clock time"),
        ]),
        Section(title: "Energy", entries: [
            Entry(code: ":fire:", glyph: "🔥", keywords: "fire hot streak"),
            Entry(code: ":sparkles:", glyph: "✨", keywords: "sparkles magic"),
            Entry(code: ":star:", glyph: "⭐", keywords: "star"),
            Entry(code: ":muscle:", glyph: "💪", keywords: "muscle strong"),
            Entry(code: ":zap:", glyph: "⚡", keywords: "zap lightning energy"),
            Entry(code: ":sunrise:", glyph: "🌅", keywords: "sunrise dawn morning ortus"),
            Entry(code: ":sunrise_over_mountains:", glyph: "🌄", keywords: "sunrise mountain dawn"),
            Entry(code: ":sun_with_face:", glyph: "🌞", keywords: "sun face bright"),
            Entry(code: ":coffee:", glyph: "☕", keywords: "coffee morning caffeine"),
            Entry(code: ":tea:", glyph: "🍵", keywords: "tea drink"),
            Entry(code: ":headphones:", glyph: "🎧", keywords: "headphones music focus"),
            Entry(code: ":musical_note:", glyph: "🎵", keywords: "music note"),
        ]),
        Section(title: "Away", entries: [
            Entry(code: ":sleeping:", glyph: "😴", keywords: "sleep tired bed"),
            Entry(code: ":zzz:", glyph: "💤", keywords: "zzz sleep"),
            Entry(code: ":yawning_face:", glyph: "🥱", keywords: "yawn tired"),
            Entry(code: ":face_with_thermometer:", glyph: "🤒", keywords: "sick fever"),
            Entry(code: ":mask:", glyph: "😷", keywords: "sick mask"),
            Entry(code: ":palm_tree:", glyph: "🌴", keywords: "palm tree vacation"),
            Entry(code: ":beach_with_umbrella:", glyph: "🏖️", keywords: "beach vacation pto"),
            Entry(code: ":knife_fork_plate:", glyph: "🍽️", keywords: "lunch food eating"),
            Entry(code: ":hamburger:", glyph: "🍔", keywords: "lunch burger food"),
            Entry(code: ":walking:", glyph: "🚶", keywords: "walking break afk"),
            Entry(code: ":runner:", glyph: "🏃", keywords: "running exercise away"),
            Entry(code: ":house_with_garden:", glyph: "🏡", keywords: "home wfh"),
            Entry(code: ":airplane:", glyph: "✈️", keywords: "airplane travel"),
        ]),
        Section(title: "Signals", entries: [
            Entry(code: ":speech_balloon:", glyph: "💬", keywords: "speech bubble default chat"),
            Entry(code: ":calendar_spiral:", glyph: "🗓️", keywords: "meeting calendar"),
            Entry(code: ":phone:", glyph: "☎️", keywords: "phone call"),
            Entry(code: ":telephone_receiver:", glyph: "📞", keywords: "phone call"),
            Entry(code: ":video_camera:", glyph: "📹", keywords: "video meeting call"),
            Entry(code: ":mega:", glyph: "📣", keywords: "megaphone announce"),
            Entry(code: ":eyes:", glyph: "👀", keywords: "eyes looking watching"),
            Entry(code: ":red_circle:", glyph: "🔴", keywords: "red circle busy live"),
            Entry(code: ":large_green_circle:", glyph: "🟢", keywords: "green circle available"),
            Entry(code: ":large_yellow_circle:", glyph: "🟡", keywords: "yellow circle"),
            Entry(code: ":large_purple_circle:", glyph: "🟣", keywords: "purple circle"),
            Entry(code: ":hand:", glyph: "✋", keywords: "hand stop wait"),
        ]),
    ]

    /// Flat lookup: shortcode → glyph. Built once.
    static let glyphsByCode: [String: String] = {
        var map: [String: String] = [:]
        for section in sections {
            for entry in section.entries {
                map[entry.code] = entry.glyph
            }
        }
        return map
    }()

    /// Returns the Unicode glyph for a Slack shortcode, or `nil` if unknown
    /// (likely a custom workspace emoji like `:my-logo:`).
    static func glyph(for code: String) -> String? {
        let normalized = normalize(code)
        return glyphsByCode[normalized]
    }

    /// Slack treats `:foo:` and `foo` interchangeably in some places; normalize to
    /// `:foo:` so lookups are consistent.
    static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix(":") && trimmed.hasSuffix(":") { return trimmed }
        return ":\(trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ":"))):"
    }

    /// Case-insensitive fuzzy search over name + keywords.
    static func search(_ query: String) -> [Entry] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var results: [Entry] = []
        for section in sections {
            for entry in section.entries {
                let haystack = entry.code.lowercased() + " " + entry.keywords
                if haystack.contains(q) {
                    results.append(entry)
                }
            }
        }
        return results
    }
}
