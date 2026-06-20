# Ortus

## FOR HUMANS - WHAT IS ORTUS

**A macOS menu bar app that blocks Slack during focus hours so you can do deep work.**

Ortus kills Slack when focus mode activates (manually or on a schedule) and keeps it dead — if you try to reopen it, Ortus terminates it again. When focus ends, Slack comes back automatically.

There's no "End Focus" button to tempt you. Quitting the app during focus is blocked. The only escape hatch is a hidden emergency end that's rate-limited to once per week.

While focused, your Slack profile flips to a configurable "Ortus mode" status with Do Not Disturb engaged, so teammates see you're heads-down. The status auto-clears when focus ends.

An optional in-app AI chat lets you query Slack without unblocking it — powered by your local Claude Code install and its Slack MCP server.

### Why

Slack is the biggest productivity killer in most people's workday. "Just checking one message" turns into 30 minutes of context-switching. Existing focus tools set DND status or mute notifications — but Slack is still *right there*, one click away.

Ortus takes a harder line: Slack is gone. Not minimized, not muted — terminated. And it can't come back until your focus time is over. This creates the kind of forced boundary that actually works for deep work.

### Features

- **Menu bar app** — lives in your menu bar with a sunrise icon, no dock icon
- **Slack blocking** — kills Slack and prevents relaunch during focus
- **Scheduled focus** — set recurring focus hours (e.g., weekdays 9am-12pm)
- **Manual focus** — start a timed session with a slider (15 min to 4 hours)
- **Quit blocking** — Cmd+Q and Dock quit are blocked during focus
- **Emergency end** — hidden in Settings, rate-limited to once per week
- **Developer mode** — tap the version number 7 times to get a dev-only end button
- **Slack status sync** — auto-sets your Slack profile status + DND during focus, clears on exit
- **AI Slack assistant** — chat with your Slack workspace through Claude Code without unblocking Slack

### Setup from scratch on a Mac

If you're starting from a fresh Mac and want to install and run Ortus, follow these steps in order.

#### 1. Requirements

- **macOS 14 Sonoma or later** (15 Sequoia / 26 Tahoe both work). Older versions are not supported.
- **Apple Silicon or Intel Mac.**
- **Swift toolchain.** Either:
  - Apple CommandLineTools — install with `xcode-select --install` from Terminal (small, ~1.5 GB), or
  - Full Xcode from the App Store (much larger, only needed if you want to develop Ortus itself).

#### 2. Get the code and build

```bash
git clone https://github.com/scandolo/Ortus.git
cd Ortus
./build.sh         # Compiles Swift sources, produces Ortus.app
open Ortus.app     # Launches it
```

The first launch may show a Gatekeeper warning ("Ortus can't be opened because the developer cannot be verified"). To bypass once:
1. Right-click `Ortus.app` in Finder → **Open** → **Open** in the prompt.
2. Or, System Settings → Privacy & Security → scroll to the "Ortus was blocked" entry → **Open Anyway**.

Once launched, Ortus appears as a sunrise icon in your menu bar. There is no Dock icon (it's a menu bar app).

#### 3. Optional — enable AI chat (Claude Code subprocess)

Ortus's Chat tab runs your local `claude` CLI as a subprocess and talks to your Slack workspace through Claude Code's built-in Slack MCP. Nothing about the chat lives inside Ortus — no API keys, no custom tool definitions.

```bash
# Install Claude Code (one-time):
npm install -g @anthropic-ai/claude-code

# Verify it's on PATH:
which claude       # should print something like /opt/homebrew/bin/claude
claude --version   # should print "2.x.x (Claude Code)"
```

Then in Claude Code, authenticate (`claude` once and follow prompts) and connect the Slack MCP server (Claude Code → `/mcp` → add Slack). Ortus auto-detects the `claude` binary; if you've installed it somewhere unusual, set the path in **Settings → AI chat → Custom binary path**.

#### 4. Optional — enable Slack status sync during focus

When focus mode activates, Ortus can set your Slack profile status to "Ortus mode" (or anything you want) and engage Do Not Disturb. Teammates see you're heads-down; you literally can't open Slack to be tempted by it.

You need a Slack app you own — takes about a minute:

1. Open [api.slack.com/apps](https://api.slack.com/apps?new_app=1) → **Create New App** → **From scratch**.
   - **App Name:** anything (e.g. "My Ortus")
   - **Workspace:** the workspace you want status updates in
2. Once created, in the left sidebar go to **OAuth & Permissions**.
3. Scroll to **Redirect URLs** → **Add New Redirect URL** → paste **exactly**:

    ```
    http://127.0.0.1:53124/callback
    ```

    Click **Add**, then **Save URLs**. (This must match what Ortus uses for the loopback OAuth callback — Slack does strict exact matching.)
4. Scroll further down to **User Token Scopes** → **Add an OAuth Scope** → add:
   - `users.profile:write`
   - `dnd:write`
5. Go to **Basic Information** in the left sidebar → scroll to **App Credentials** → copy your **Client ID** and **Client Secret**.
6. In Ortus → menu bar icon → ⚙ Settings → **Slack status** card → **Set up** → paste Client ID and Client Secret → **Connect Slack**.
7. A browser tab opens with Slack's authorization page. Click **Allow**. The tab will close itself and Ortus's Settings will show "Connected to {your workspace}".

After this you can enable **Update Slack status during focus**, customize the status text + emoji, and toggle **Snooze notifications (DND)**.

#### 5. Optional — start at login + scheduling

- **Launch at login:** Settings → Preferences → toggle "Launch at login".
- **Recurring focus hours:** Schedule tab → "+ Add schedule" → name it, pick days, set start/end time. Schedules fire automatically.

### How It Works

1. When focus activates, Ortus terminates all Slack processes
2. It monitors app launches and kills Slack if it tries to start
3. It calls Slack's `users.profile.set` + `dnd.setSnooze` to mirror "Ortus mode" on the server side
4. An `NSApplicationDelegate` intercepts `Cmd+Q` and termination requests
5. When focus ends, monitoring stops, Slack relaunches (if enabled), status clears, DND ends

---

## FOR LLMs - HOW TO WORK IN THIS REPO

### Architecture

Ortus is a SwiftUI macOS menu bar app built with Swift Package Manager. It runs as a `MenuBarExtra` with `.window` style (popover panel). No dock icon (`LSUIElement = true` in Info.plist).

The AI chat feature is **not** baked into the app — it spawns the user's local `claude` CLI as a subprocess (`Process()` with `--output-format stream-json`) and streams JSON events back into the chat UI. Slack queries inside the chat route through Claude Code's Slack MCP server, not through Ortus's own Slack client.

### Project Structure

```
Ortus/
├── Package.swift                 # SPM config, macOS 14+, swift-tools 6.0, single executable target
├── build.sh                      # Build script: kills old instances, swift build, creates .app bundle
├── Ortus/
│   ├── OrtusApp.swift            # @main entry, MenuBarExtra scene, AppDelegate for quit blocking
│   ├── Models/
│   │   ├── ChatMessage.swift     # role + content + timestamp + kind (text / toolUse / error)
│   │   ├── FocusSchedule.swift   # Schedule model + Weekday enum + ScheduleStore (UserDefaults)
│   │   └── SlackModels.swift     # OAuth response types + generic ok/error response
│   ├── Services/
│   │   ├── FocusManager.swift    # Core: focus state, Slack kill/monitor, schedules, emergency end, status apply/clear
│   │   ├── ClaudeCodeService.swift # Spawns `claude` CLI subprocess, parses stream-json, publishes ChatMessages
│   │   ├── SlackService.swift    # Status + DND writer (users.profile.set, dnd.setSnooze/endSnooze)
│   │   ├── SlackOAuthService.swift # OAuth flow with loopback HTTP server (write scopes only)
│   │   └── KeychainService.swift # macOS Keychain wrapper for Slack credentials
│   └── Views/
│       ├── OrtusTheme.swift      # Design system: glass cards, capsule buttons, materials, tokens
│       ├── ContentView.swift     # Tab container with floating glass tab bar
│       ├── FocusView.swift       # Focus status, timer, start button (no end button)
│       ├── ScheduleView.swift    # Schedule list with inline editing (no sheets)
│       ├── ChatView.swift        # AI chat: text bubbles, tool-use chips, error pills, stop/clear
│       └── SettingsView.swift    # AI chat config, Slack status section, preferences, emergency, about
```

### Key Design Decisions

**No End Focus button**: The core UX insight is that having an easy escape defeats the purpose. The button is intentionally removed. Emergency end exists in Settings but is rate-limited to 1/week. Developer mode (7 taps on version label) adds a dev-only end button to FocusView.

**Inline editing in ScheduleView**: `.sheet()` creates a new `NSWindow` which causes the `MenuBarExtra` panel to lose key window status and auto-dismiss. The fix is to expand an inline editor in-place using state variables (`editingScheduleID` / `isAddingNew`). `ScrollView` + `VStack` replaces `List` to avoid `NSTableView` focus issues. `Button` wraps only the text label (not the toggle) to prevent tap gesture conflicts.

**Quit blocking via AppDelegate**: `NSApplicationDelegateAdaptor` with `applicationShouldTerminate` returning `.terminateCancel` when focus is active. This blocks Cmd+Q, Dock quit, and programmatic termination.

**Emergency end keeps Slack blocked**: `emergencyEndFocusSession()` sets `isEmergencyEnded = true`, clears focus UI state, but does NOT stop launch monitoring. The schedule evaluator checks `originalFocusEndTime` and only cleans up monitoring when that time passes. Status is cleared immediately so teammates aren't confused.

**Claude Code subprocess for chat**: Ortus does **not** hold an Anthropic API key. It spawns `claude -p <msg> --output-format stream-json --verbose --model sonnet --append-system-prompt <ortus context> --permission-mode bypassPermissions` per turn, using `--session-id <uuid>` on the first turn and `--resume <uuid>` for follow-ups. Stop button calls `process.terminate()`; Clear resets the session UUID.

**Slack OAuth scoped to writes only**: After moving chat to Claude Code, the only thing Ortus's Slack OAuth does is set status and DND. Scopes are narrowed to `users.profile:write,dnd:write`. All read-side queries (search, history, channels, users) go through Claude Code's MCP.

**Status update fire-and-forget**: `applySlackStatusForFocus` / `clearSlackStatusForFocus` in FocusManager use `Task { try? await ... }` so a Slack outage doesn't block focus state transitions.

**StateObject injection on appear**: Cross-service wiring (FocusManager.slackService = slackService) happens in `.onAppear`, not `App.init` — accessing `_focusManager.wrappedValue` in init creates a phantom StateObject instance on macOS 14+.

**Glass surfaces via Materials**: Cards use `.regularMaterial` in continuous RoundedRectangles; floating toolbars use Capsules. On macOS 26 (Tahoe) the system renders these with the new Liquid Glass treatment automatically, so the look is correct on both Sequoia and Tahoe without API drift. Inner highlight strokes + soft shadows add depth.

### State Management

- `FocusManager` (ObservableObject, `@MainActor`): central state for focus sessions, schedules, emergency end, Slack status apply/clear
  - `@Published`: `isInFocus`, `isEmergencyEnded`, `focusEndTime`, `originalFocusEndTime`, `isInGracePeriod`, `gracePeriodEndTime`, `schedules`, `currentSessionName`
  - `@AppStorage`: `relaunchSlackOnEnd`, `showNotifications`, `lastEmergencyEndTimestamp`, `developerModeEnabled`, `slackStatusEnabled`, `slackStatusText`, `slackStatusEmoji`, `slackDndEnabled`
  - `slackService: SlackService?` injected by OrtusApp.onAppear
  - Schedule evaluation runs on a 30-second timer
- `ClaudeCodeService`: subprocess manager + stream-json parser, owns the chat message list
- `SlackService`: status/DND writer
- `SlackOAuthService`: loopback OAuth flow (write scopes only)
- All four are passed via `.environmentObject()`
- Slack credentials stored in macOS Keychain via `KeychainService`

### Design System — "First Light" (OrtusTheme.swift)

A calm, premium, dawn-over-the-horizon aesthetic built on Apple's HIG. `OrtusTheme.swift`
is the single source of truth — every view reaches for its tokens (no raw hex, no bare
`.system(size:)`).

- **One accent**: a warm "first light" coral-amber (`accent`, light/dark adaptive) drives
  every interactive affordance. The multi-stop **dawn gradient** (`dawnColors` /
  `dawnGradient` / `dawnGlow` — predawn indigo → mauve → coral → gold) is reserved for
  brand + hero moments only (the timer ring/aura, the sunmark, the idle hero, the app icon).
- **Brand glyph**: `OrtusSunmark` — an original half-sun-over-horizon mark drawn in pure
  SwiftUI. Used in the idle hero, the About card, empty states; rasterised (via
  `generate_app_icon.py` + `iconutil`) for the Finder app icon.
- **Surfaces**: solid adaptive `canvas`/`canvasDeep` (a vertical "dawn sky" wash, never a
  translucent material — avoids wallpaper bleed), `cardSurface` (e1) and `cardRaised` (e2/
  popovers/nav) which lift above the canvas, `inputSurface` recessed below cards.
- **Shapes**: continuous corner radius everywhere. `radiusSM(10)`, `radiusMD(14)`,
  `radiusLG(20)`, `radiusXL(28)`. Capsules for pill controls.
- **Elevation**: a three-step soft shadow scale (`OrtusTheme.Elevation.e1/e2`).
- **Typography** (`Typo`): SF Pro for text, SF Pro Rounded for the hero clock & display
  numerals; tabular figures for anything that ticks.
- **Motion** (`Motion`): 140–260ms ease-out / spring-on-press tokens; respects reduced-motion.
- **Spacing**: 4pt grid — `spacingXS(4)` … `spacingXL(32)`.
- **Components**: `.ortusCard()` / `.ortusCard(tint:)` / `.ortusCard(raised:)`,
  `OrtusPrimaryButtonStyle` (coral capsule CTA), `OrtusSecondaryButtonStyle` (glass capsule),
  `OrtusDestructiveButtonStyle` (ember capsule), `OrtusGhostButtonStyle`, `OrtusTextFieldStyle`
  (recessed input with focus glow), `OrtusEmptyState`, `OrtusSectionHeader`, `OrtusSunmark`,
  `VibrantBackground`. The nav is a floating segmented capsule with a sliding
  `matchedGeometryEffect` selection.

### Landing page (`landing/`)

A standalone, dependency-free marketing site (`index.html` / `styles.css` / `script.js`)
in the same "First Light" language: a cinematic dark dawn hero with a faithful HTML/CSS
mock of the app popover, a bento feature grid with original inline-SVG icons (drawn in the
sunmark's line language), how-it-works, FAQ, and a dawn-gradient CTA. Open `landing/index.html`
directly in a browser — no build step. Brand assets in `landing/assets/` (`sunmark.svg`,
`favicon.svg`, `app-icon.png`).

### Build & Run

```bash
./build.sh         # swift build, creates Ortus.app bundle
open Ortus.app     # Launch from .app bundle
```

Direct binary execution is blocked (`chmod -x` on `.build/debug/Ortus`) to avoid duplicate System Settings entries.

### Dependencies

None. Pure Swift/SwiftUI with Apple frameworks only (AppKit, Security, Network, UserNotifications, ServiceManagement). The Claude Code subprocess is the user's own install, spawned via `Process()`.

### Integrations

- **Claude Code (subprocess)**: ` /opt/homebrew/bin/claude -p <prompt> --output-format stream-json --verbose --model sonnet --append-system-prompt <prompt> --permission-mode bypassPermissions [--session-id | --resume]`. Path auto-detected; custom path settable in Settings. Uses the user's Claude auth and MCP config — Slack queries route through their Slack MCP server.
- **Slack Web API (status only)**: OAuth v2 user token flow with loopback HTTP server. Scopes: `users.profile:write,dnd:write`. Endpoints: `users.profile.set`, `dnd.setSnooze`, `dnd.endSnooze`.
