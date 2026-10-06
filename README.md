<div align="center">

<img src="landing/assets/favicon.svg" width="72" height="72" alt="Ortus" />

# Ortus

**The most hardcore focus app for makers.**
A Mac menu-bar app that blocks distractions so you can do deep work.

[![Website](https://img.shields.io/badge/website-ortus.up.railway.app-FD9E4D)](https://ortus.up.railway.app)
[![Latest release](https://img.shields.io/github/v/release/scandolo/Ortus?color=FD9E4D&label=download)](https://github.com/scandolo/Ortus/releases/latest)
[![Platform](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple&logoColor=white)](https://ortus.up.railway.app)
[![Built with SwiftUI](https://img.shields.io/badge/SwiftUI-Swift%206-FA7343?logo=swift&logoColor=white)](Package.swift)
[![License: MIT](https://img.shields.io/badge/license-MIT-FD9E4D)](LICENSE)

[Website](https://ortus.up.railway.app) · [Install](#install) · [How it works](#how-it-works) · [Development](#development)

<br />

<img src="landing/assets/mockup.png" width="720" alt="Ortus running a locked deep-focus session in the macOS menu bar" />

</div>

---

## What is Ortus?

Ortus lives in your Mac menu bar and blocks your biggest distraction while you do
deep work. When focus mode starts (manually or on a schedule), Ortus terminates
Slack and keeps it terminated: reopen it and Ortus closes it again. When your
session ends, Slack comes back on its own.

There is no "End Focus" button to talk yourself into. Quitting Ortus mid-session
is blocked too. The only escape hatch is a hidden emergency end, rate-limited to
once per week.

An optional AI chat (powered by your own Claude) lets you check what is happening
in Slack without opening it, so you stay heads-down.

> Willpower runs out. A locked session doesn't. Ortus holds the line so you can
> stay in the work.

## Compare the two local designs

```bash
./build.sh native
./build.sh glass
python3 scripts/install-preview.py --variant native
python3 scripts/install-preview.py --variant glass
```

Open **Ortus Native** and **Ortus Glass** from Applications. Their first windows
position themselves side by side. Native uses compact solid surfaces; Glass uses
softer materials and a circular active timer. Both have the same blocking features,
keyboard controls, draft recovery, validation, and emergency rules. Preferences
are separate. Both start with Focus Time **off** until you enable it. New schedules are also
saved off by default. Every preset states its actual coverage, including partial
Slack app or website selections.

The browser companion is shared at `/Applications/Ortus Preview Browser`; it
uses the appearance of the active controller. Reload its card once in your
browser's extensions page after updating these builds. You do not need to load
a second extension. Only one app can own an active focus session. The other can
be explored and configured safely; it cannot erase the active app's website rules.
Quit an older Ortus Preview before starting focus in a comparison app.

The optional Assistant retains unsent drafts, offers retry after a failed request,
and uses Claude Code’s normal permission mode. It does not bypass tool approval.

The local builds are ad-hoc signed and publish no release. The public installer
and published GitHub release are unaffected by building these candidates.

## Local preview: apps and websites per schedule

This branch includes an unreleased blocking preview. The public installer still
ships the published release; building this branch does not publish or update it.

```bash
./build.sh preview
python3 scripts/install-preview.py
open "/Applications/Ortus Preview.app"
```

The preview has its own app identity and focus preferences. It does not enable
launch at login automatically, and its release updater is disabled. Quit the
regular Ortus app before testing to avoid having two sets of schedules running.
Local builds use ad-hoc signing and require no keychain or administrator setup.

### Choose what each schedule blocks

In **Schedules**, create or edit a schedule and choose Gmail, LinkedIn, Slack,
custom website domains, and applications from your Mac. The default **Focus Time**
schedule is weekdays **09:00–12:00** and selects Gmail, LinkedIn, and Slack
(including Slack in the browser). Manual focus has its own saved selection.

Websites include all subdomains. Gmail uses `mail.google.com` and `gmail.com`, so
Google Docs and other Google services remain available. Applications are matched
by bundle identifier, including reopened instances. Finder, System Settings, and
Ortus itself cannot be selected. Selected applications are closed during focus;
save work in those applications before starting.

Overlapping schedules combine their selections and expire independently.
Overnight schedules use the weekday on which they start. Active sessions keep a
snapshot of their choices; their schedule cannot be weakened while it is running.
Manual sessions survive restarting Ortus. Grace cancellation only cancels the
manual session; emergency end releases all current targets and suppresses the
current schedule window, including across restarts.

### Connect Chrome, Arc, Edge, or Brave once

1. Open `arc://extensions` in Arc or `chrome://extensions` in Chrome and enable **Developer mode**.
2. Choose **Load unpacked** and select
   `/Applications/Ortus Preview Browser`.
   Choose this ordinary folder in Applications. The folder and its path are also available in **Ortus → Settings → Website blocking**.
3. Leave the companion enabled. Ortus shows the connection when the browser has
   successfully applied its rules. In Arc, you can label the connection **Arc**
   in the extension popup.

After loading, confirm the **Ortus · Website blocking** card appears and the app reports **Browser companion connected**. Website blocking is inactive until that connection exists.

Do this for each browser profile you use. Private windows need the extension's
**Allow in Incognito** setting. Safari and Firefox are not covered by this preview.
Browser extensions can be disabled or removed by their owner; this is a focus
commitment tool, not a tamper-proof parental control or device security system.

There are no administrator, Accessibility, or Apple Events permission prompts.
The extension permission to operate on websites is necessary for arbitrary domain
blocking. It redirects selected websites to a local focus page, handles tabs that
are already open, and blocks background requests to selected domains. At the end,
the page offers to return to the original URL. It does not reload tabs automatically.

### How the blocking pieces fit together

- `Sources/OrtusCore`: validated targets, saved schedules, session snapshots,
  overlap/overnight resolution, browser deadlines, and the native message format.
- `ApplicationBlocker`: native macOS app termination and relaunch monitoring.
- `WebsiteBlockingService`: publishes a local policy with a short heartbeat lease.
- `OrtusBrowserBridge`: unprivileged Native Messaging process; reads only that
  policy and exchanges connection acknowledgements with the extension.
- `BrowserExtension`: Chromium Manifest V3 session rules, open-tab enforcement,
  and the local blocked page. No browsing URLs or page content are sent to Ortus.

The browser clears stale rules within 20 seconds if Ortus stops updating its
heartbeat; it also removes rules at their individual deadlines and clears rules
on a native connection failure. This avoids leaving websites stuck behind an
abandoned session. Existing credentials and network settings are untouched.

The shared target/session model is independent of these two enforcement methods.
A future Safari companion or signed macOS network filter can use the same schedule
and deadline policy without redesigning the schedule editor.

### Verify without using the screen

```bash
swift run OrtusCoreChecks
node --test BrowserExtension/tests/*.test.js
bash scripts/test-app-blocking.sh
```

The Swift checks run with Command Line Tools alone; they do not require Xcode's
XCTest/Testing frameworks. App integration checks launch only a disposable,
windowless fixture app. For a real browser integration check, install Python
Playwright and its Chromium runtime, then run `python3 scripts/test-browser.py`.
That test uses a disposable **headless** profile, a temporary native host, and
local website fixtures. It never opens personal browser profiles or contacts Gmail.

## Install

### One-line install (recommended)

```bash
curl -fsSL https://ortus.up.railway.app/install.sh | bash
```

This downloads the latest release into `/Applications` and launches it. Because it
installs via the terminal (not a browser download), macOS does not quarantine the
app, so Gatekeeper does not block it. Requires macOS 14 or later.

### Download manually

Grab the latest `Ortus-macOS.zip` from the
[Releases page](https://github.com/scandolo/Ortus/releases/latest), unzip it, and
move `Ortus.app` to `/Applications`.

### Build from source

```bash
git clone https://github.com/scandolo/Ortus.git
cd Ortus
./build.sh        # kills running instances, builds, and creates Ortus.app
open Ortus.app
```

Requires macOS 14+ and the Swift 6 toolchain (Xcode).

### AI chat (optional)

To enable the AI Slack assistant, add a Claude API key and connect Slack via OAuth
in **Settings**. Credentials are stored in the macOS Keychain.

## How it works

1. When focus activates, Ortus terminates all Slack processes.
2. It watches for app launches and closes Slack again if it tries to start.
3. An `NSApplicationDelegate` intercepts `Cmd+Q` and termination requests so you
   cannot quit your way out.
4. When focus ends (or the scheduled window passes), monitoring stops and Slack
   relaunches on its own.

## Privacy

Your Slack token and Claude API key are stored in the macOS Keychain and are only
ever sent to Slack and Anthropic respectively. Ortus sends anonymous, aggregate
usage events (via PostHog) to help improve the app. There are no accounts.

## Development

Ortus is a SwiftUI macOS menu-bar app built with Swift Package Manager. It runs as
a `MenuBarExtra` with `.window` style (a popover panel) and no dock icon
(`LSUIElement = true`).

### Project structure

```
Ortus/
├── Package.swift              # SPM config, macOS 14+, single executable target
├── build.sh                   # Build script: kills instances, builds, bundles Ortus.app
├── landing/                   # The marketing site (ortus.up.railway.app), served by Caddy
└── Ortus/
    ├── OrtusApp.swift         # @main entry, MenuBarExtra scene, quit-blocking AppDelegate
    ├── Models/                # ChatMessage, FocusSchedule + ScheduleStore, Slack API types
    ├── Services/
    │   ├── FocusManager.swift # Coordinates sessions, selected targets, schedules, emergency end
    │   ├── ClaudeService.swift# Claude API client with an agentic tool-use loop
    │   ├── SlackService.swift # Slack Web API client
    │   ├── SlackOAuthService.swift # OAuth flow via a loopback HTTP server
    │   ├── KeychainService.swift   # macOS Keychain wrapper for secrets
    │   └── Analytics.swift    # Thin PostHog wrapper (anonymous usage events)
    ├── Views/
    │   ├── OrtusTheme.swift   # Design system: sunrise-amber accent, glass materials, tokens
    │   ├── ContentView.swift  # Tab container (Focus, Schedule, Chat, Settings)
    │   ├── FocusView.swift    # Timer, start button, grace period (no end button)
    │   ├── ScheduleView.swift # Recurring schedules with inline editing
    │   ├── ChatView.swift     # AI chat with Claude
    │   └── SettingsView.swift # API keys, Slack OAuth, preferences, emergency end
    └── Tools/
        └── SlackTools.swift   # Tool definitions for Claude's tool-use
```

### Key design decisions

- **No End Focus button.** An easy escape defeats the purpose. Emergency end lives
  in Settings and is gated to once per calendar week. Developer mode (tap the version
  label 7 times) adds a dev-only end button.
- **Inline editing in ScheduleView.** `.sheet()` spawns a new `NSWindow`, which makes
  the `MenuBarExtra` panel lose key-window status and dismiss. Schedules are edited
  in place with state variables instead.
- **Quit blocking via AppDelegate.** `applicationShouldTerminate` returns
  `.terminateCancel` while focus is active, blocking Cmd+Q, Dock quit, and
  programmatic termination.
- **Glass material design.** Cards and the status ring use `.ultraThinMaterial` with
  continuous (supercircle) corner radii, adapting to light and dark mode.

### Dependencies

[PostHog](https://github.com/PostHog/posthog-ios) for anonymous usage analytics.
Everything else is Apple frameworks only (AppKit, Security, Network,
UserNotifications, ServiceManagement).

## License

[MIT](LICENSE). Free and open source.

<div align="center"><sub>Carpe lucem.</sub></div>
