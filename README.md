# Ortus

**A macOS menu bar app that blocks Slack during focus hours so you can do deep work.**

Ortus kills Slack when focus mode activates (manually or on a schedule) and keeps it dead — if you try to reopen it, Ortus terminates it again. When focus ends, Slack comes back automatically.

There's no "End Focus" button to tempt you. Quitting the app during focus is blocked. The only escape hatch is a hidden emergency end that's rate-limited to once per week.

An optional AI chat (powered by Claude) lets you check what's happening in Slack without actually opening it.

## Why

Slack is the biggest productivity killer in most people's workday. "Just checking one message" turns into 30 minutes of context-switching. Existing focus tools set DND status or mute notifications — but Slack is still *right there*, one click away.

Ortus takes a harder line: Slack is gone. Not minimized, not muted — terminated. And it can't come back until your focus time is over. This creates the kind of forced boundary that actually works for deep work.

## Features

- **Menu bar app** — lives in your menu bar with a sunrise icon, no dock icon
- **Slack blocking** — kills Slack and prevents relaunch during focus
- **Scheduled focus** — set recurring focus hours (e.g., weekdays 9am-12pm)
- **Manual focus** — start a timed session with a slider (15 min to 4 hours)
- **Quit blocking** — Cmd+Q and Dock quit are blocked during focus
- **Emergency end** — hidden in Settings, rate-limited to once per week
- **Developer mode** — tap the version number 7 times to get a dev-only end button
- **AI Slack assistant** — ask Claude about your Slack channels without opening Slack
- **Slack OAuth** — connects to your workspace for AI features

## Setup

```bash
# Build
./build.sh

# Run
open Ortus.app
```

Requires macOS 13+ and Xcode/Swift toolchain.

For the AI chat feature (optional): add a Claude API key and connect Slack via OAuth in Settings.

## How It Works

1. When focus activates, Ortus terminates all Slack processes
2. It monitors app launches and kills Slack if it tries to start
3. An `NSApplicationDelegate` intercepts `Cmd+Q` and termination requests
4. When focus ends (or the schedule period passes), monitoring stops and Slack relaunches

---

<details>
<summary><strong>Technical Reference (for AI models and contributors)</strong></summary>

## Architecture

Ortus is a SwiftUI macOS menu bar app built with Swift Package Manager. It runs as a `MenuBarExtra` with `.window` style (popover panel). No dock icon (`LSUIElement = true` in Info.plist).

### Project Structure

```
Ortus/
├── Package.swift              # SPM config, macOS 13+, single executable target
├── build.sh                   # Build script: kills old instances, swift build, creates .app bundle
├── Ortus/
│   ├── OrtusApp.swift         # @main entry, MenuBarExtra scene, AppDelegate for quit blocking
│   ├── Models/
│   │   ├── ChatMessage.swift  # Chat message model (role, content, timestamp)
│   │   ├── FocusSchedule.swift # Schedule model + Weekday enum + ScheduleStore (UserDefaults)
│   │   └── SlackModels.swift  # All Slack API response types (Codable)
│   ├── Services/
│   │   ├── FocusManager.swift # Core logic: focus state, Slack kill/monitor, schedules, emergency end
│   │   ├── ClaudeService.swift # Claude API client with agentic tool-use loop
│   │   ├── SlackService.swift  # Slack Web API client (search, history, channels, users)
│   │   ├── SlackOAuthService.swift # OAuth flow with loopback HTTP server
│   │   └── KeychainService.swift   # macOS Keychain wrapper for secrets
│   ├── Views/
│   │   ├── OrtusTheme.swift   # Design system: colors, spacing, radii, reusable components
│   │   ├── ContentView.swift  # Tab container (Focus, Schedule, Chat, Settings)
│   │   ├── FocusView.swift    # Focus status, timer, start button (no end button)
│   │   ├── ScheduleView.swift # Schedule list with inline editing (no sheets)
│   │   ├── ChatView.swift     # AI chat with Claude
│   │   └── SettingsView.swift # API keys, Slack OAuth, preferences, emergency end, dev mode
│   └── Tools/
│       └── SlackTools.swift   # Tool definitions for Claude's tool-use (search, history, etc.)
```

### Key Design Decisions

**No End Focus button**: The core UX insight is that having an easy escape defeats the purpose. The button is intentionally removed. Emergency end exists in Settings but is rate-limited to 1/week. Developer mode (7 taps on version label) adds a dev-only end button to FocusView.

**Inline editing in ScheduleView**: `.sheet()` creates a new `NSWindow` which causes the `MenuBarExtra` panel to lose key window status and auto-dismiss. The fix is to expand an inline editor in-place using state variables (`editingScheduleID` / `isAddingNew`). `ScrollView` + `VStack` replaces `List` to avoid `NSTableView` focus issues. `Button` wraps only the text label (not the toggle) to prevent tap gesture conflicts.

**Quit blocking via AppDelegate**: `NSApplicationDelegateAdaptor` with `applicationShouldTerminate` returning `.terminateCancel` when focus is active. This blocks Cmd+Q, Dock quit, and programmatic termination.

**Emergency end keeps Slack blocked**: `emergencyEndFocusSession()` sets `isEmergencyEnded = true`, clears focus UI state, but does NOT stop launch monitoring. The schedule evaluator checks `originalFocusEndTime` and only cleans up monitoring when that time passes.

**No Slack relaunch on app quit during focus**: The old `willTerminateNotification` observer that relaunched Slack on quit was removed — it was counterproductive since quit is now blocked during focus.

### State Management

- `FocusManager` (ObservableObject): central state for focus sessions, schedules, emergency end
  - `@Published isInFocus`, `isEmergencyEnded`, `focusEndTime`, `originalFocusEndTime`
  - `@AppStorage` for persistence: `relaunchSlackOnEnd`, `showNotifications`, `lastEmergencyEndTimestamp`, `developerModeEnabled`
  - Schedule evaluation runs on a 30-second timer
- `SlackService`, `ClaudeService`, `SlackOAuthService`: independent service objects passed via `.environmentObject()`
- Credentials stored in macOS Keychain via `KeychainService`

### Design System (OrtusTheme.swift)

- Colors: `primary` (indigo), `primaryLight` (indigo 12%), `warning` (orange), `warningLight`, `success` (green), `destructive` (red), `cardBackground`, `cardBorder`
- Spacing: 8pt grid — `spacingXS(4)`, `spacingSM(8)`, `spacingMD(16)`, `spacingLG(24)`, `spacingXL(32)`
- Corner radii: `radiusSM(8)`, `radiusMD(12)`, `radiusLG(16)`
- Components: `.ortusCard()` modifier, `OrtusPrimaryButtonStyle`, `OrtusEmptyState`, `OrtusSectionHeader`

### Build & Run

```bash
./build.sh        # Kills running instances, swift build, creates Ortus.app bundle
open Ortus.app    # Launch from .app bundle (not bare binary — avoids duplicate System Settings entries)
```

The build script also `chmod -x` on the bare binary in `.build/debug/` to prevent accidental direct execution.

### Dependencies

None. Pure Swift/SwiftUI with Apple frameworks only (AppKit, Security, Network, UserNotifications, ServiceManagement).

### API Integration

- **Claude API**: Standard Messages API with tool use. Agentic loop (max 10 iterations). Model: `claude-sonnet-4-5-20250929`. Tools defined in `SlackTools.swift`.
- **Slack API**: OAuth v2 user token flow with loopback HTTP server on localhost. User scopes: `search:read`, `channels:history`, `groups:history`, `im:history`, `mpim:history`, `users:read`, `channels:read`, `groups:read`.

</details>
