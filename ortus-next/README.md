# Ortus Next

An Electron-based reimplementation of Ortus that adopts Loom's architectural pattern: a JS shell coordinating multiple independent window surfaces, with heavy work delegated to subprocesses. Runs in parallel to the original SwiftUI Ortus — different bundle ID (`app.ortus.next`), different state dir (`~/Library/Application Support/ortus-next`), different tray icon.

## The headline feature: Intention Lock

The original Ortus's friction is at the *quit boundary* — once focus starts, you can't escape. Ortus Next adds friction at the *start boundary* too. Before any focus session begins, a full-screen overlay opens:

1. "What's the one thing you're doing right now?"
2. A text field (you must type something specific).
3. Verb chips to make it concrete (Ship / Think through / Make progress on / Write / Decide on).
4. A 20-second lock that prevents starting — you can't click into focus mindlessly.
5. While focus is active, a small **Now** widget floats in the bottom-right showing your intention + remaining time. Visible across spaces, even over full-screen apps.
6. When focus ends (natural or emergency), a **Reflection** window asks how it went. Four buttons: Shipped / Partial / Stuck / Pulled away. Optional note.
7. Every session is logged to `intentions.json`. The main window's **Intention ledger** tab shows the record over time.

No streaks. No badges. No points. Just a private, growing artifact of what you committed to and what actually happened.

## Architecture (Loom-pattern)

```
main.js                       Electron main process: app lifecycle, IPC dispatcher, tray
preload.js                    contextBridge exposing window.ortus to renderers
lib/
  state.js                    Centralized store + JSON persistence + change events
  focus.js                    Focus state machine; mediates Slack + intentions + windows
  slack.js                    pkill + poll-and-kill (the Loom equivalent of a Swift sidecar)
  intentions.js               Append-only intention log at ~/Library/Application Support/ortus-next/intentions.json
  windows.js                  Window manager — one BrowserWindow per surface
renderer/
  tray/                       Menu bar dropdown (idle + active states)
  intention/                  Full-screen Intention Lock overlay
  now/                        Floating "Now" totem (always-on-top, draggable)
  reflection/                 Post-focus reflection prompt
  main/                       Ledger + settings + about
  _shared/style.css           Design tokens shared across windows
assets/
  tray-iconTemplate.png       16×16 template icon
  tray-iconTemplate@2x.png    32×32 retina variant
```

State flows one-way: renderer dispatches an action → main process mutates the store → store emits a change → main process broadcasts a fresh snapshot to every open window. No window mutates state directly. This is Loom's "windows can only change as side effects of actions" rule.

## Run

```bash
cd ortus-next
npm install              # one-time
npm start
```

You should see a small horizon icon appear in your menu bar. Click it.

To stop the app:

```bash
pgrep -f "ortus-next/node_modules/electron" | xargs kill
```

(There's no Cmd-Q during focus by design.)

## What this MVP does

- ✅ Menu bar tray with idle and active states
- ✅ Manual focus session with duration slider (15–240 min)
- ✅ Slack killed at start; relaunched at end
- ✅ Polling-based launch monitoring (kills Slack again if it relaunches)
- ✅ Quit blocking via `app.before-quit`
- ✅ Intention Lock overlay (the new feature)
- ✅ Floating Now widget
- ✅ Post-focus reflection
- ✅ Intention ledger in main window with stats
- ✅ JSON persistence (intentions + app state)

## What's deferred to next sessions

- Slack OAuth + status / DND sync (the original Ortus's `SlackService`)
- Claude Code subprocess chat (the original Ortus's `ClaudeCodeService`)
- Scheduled focus (recurring focus hours)
- Emergency end weekly rate limit UI (the limit is enforced in `focus.js`, but the UX could be more graceful)
- Auto-update via Squirrel + electron-builder packaging
- Native crash reporting (Crashpad → endpoint)
- LSUIElement enforced via Info.plist (currently via `app.dock.hide()`, which works the same)

## How this differs architecturally from the SwiftUI Ortus

| | SwiftUI Ortus | Ortus Next (this) |
|---|---|---|
| Runtime | Swift, single process | Electron, main + GPU + Network + N renderers |
| Surfaces | One `MenuBarExtra` popover with tab bar | 5 independent `BrowserWindow`s |
| State | `ObservableObject` + `@Published` | Singleton EventEmitter store + IPC broadcasts |
| Slack control | `NSWorkspace.shared.runningApplications` + `terminate()` | `pkill` + poll, Loom-style sidecar pattern (no Swift binary needed yet) |
| Quit block | `applicationShouldTerminate` returning cancel | `app.before-quit` with `e.preventDefault()` |
| Persistence | `@AppStorage` (UserDefaults) | `state.json` + `intentions.json` in user data dir |
| AI / Slack reads | `claude` CLI subprocess (already a subprocess-over-stdio pattern) | Deferred; same pattern will work |
| Bundle | ~5–10 MB Swift binary | ~200 MB Electron app |
| Cold start | Instant | ~500ms (Chromium boot) |
| Mac-native feel | Materials → Liquid Glass on Tahoe | Vibrancy + custom CSS — close but not pixel-identical |

The win we got from the new architecture: **multiple simultaneous surfaces**. The Intention Lock + floating Now widget + Reflection window cannot all coexist gracefully in a single `MenuBarExtra` popover — that's the one Loom-pattern advantage that genuinely buys a smoother UX for this app.
