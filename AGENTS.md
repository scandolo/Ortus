# Notes for coding agents

`CLAUDE.md` is a symlink to this file. For what Ortus is and how the code is laid
out, read `README.md`. This repo is public.

## Backlog

The backlog for Ortus is the Notion database **Ortus backlog**
(https://app.notion.com/p/9b7c57bae4c94a2d9498a6beb6cef65f), a board grouped by Status.
Use the Notion tools to read and update it.

- Statuses: **Idea → Triaged → Building → Shipped**.
- An idea you find or suggest goes in as **Idea** with a one-line Summary, Area and
  Source. Check for an existing card first.
- **Never move a card to Triaged yourself.** It moves only after the maintainer has
  said what it means, what we want and whether it makes sense. Record that input
  on the card.
- Work from Triaged cards. Set Building when you start and Shipped when it's merged,
  and add the PR to the card.

## Releasing: main = release

- Every push to `main` that touches `Ortus/`, `Sources/`, `BrowserExtension/`,
  `Package.*` or `build.sh` publishes a GitHub release
  (`.github/workflows/release.yml`). Users then see "Update available" in Settings.
  **Merging is shipping**: get the maintainer's OK before merging.
- Don't bump the version for normal changes. CI releases the latest version with
  its patch bumped (1.1.0 → 1.1.1) and sets `CFBundleVersion` to the commit count.
- For a minor or major release, set a higher `CFBundleShortVersionString` in
  `Ortus/Info.plist` in the PR. A higher version there wins over the automatic bump.
- `Info.plist` on `main` often shows an older version than the latest release.
  That's expected: CI writes the real version into its own checkout only.
- Release builds are universal (Apple silicon + Intel). When the Developer ID secrets
  listed in `release.yml` are set, CI signs with the hardened runtime, notarizes with
  `scripts/notarize.sh` and also publishes `Ortus.dmg`; without them it falls back to
  an ad-hoc signed zip.
- Bundle IDs are `com.ortusmode.app` and `com.ortusmode.preview`. Older builds used
  `com.ortus.*`; `OrtusApp` copies their preferences over once on first launch.

## Checks

- Build: `swift build`, or `./build.sh` for a bundled `Ortus Preview.app`.
- CI builds every PR that touches the app with the release toolchain (Xcode 16) and
  runs the core checks (`.github/workflows/checks.yml`). Your local Swift may be newer
  and more lenient, so wait for it to pass before merging.
- Core checks: `swift run OrtusCoreChecks`
- Extension tests: `cd BrowserExtension && npm test` (needs Node)
- UI: `scripts/snapshot.sh <dir> [--session]` (see below). Design rules live at the top
  of `Ortus/Views/OrtusTheme.swift`.

## Testing changes locally

The maintainer uses the installed release every day, often mid-session. Nothing you
build or run may touch it.

**Two identities.** Only CI's `./build.sh release` builds the release (`Ortus`,
`com.ortusmode.app`). Every local build, `./build.sh` and `./build.sh preview`, is
**Ortus Preview** (`com.ortusmode.preview`) with its own settings, session lock,
browser companion and login item. A preview session never ends, blocks or changes the
release's. Never run a release-identity build on the maintainer's Mac.

**Telling them apart.** A preview shows a **P** next to the sunrise in the menu bar,
and Settings names it "Ortus Preview · <branch> · <commit>". The release shows a plain
version ("Ortus 1.1.22").

**One preview at a time.** There is one preview slot, `/Applications/Ortus Preview.app`.
Branches in different workspaces take turns: installing one replaces the other.

- **You check visuals** with `scripts/snapshot.sh <dir> [--session]`. It renders every
  panel state from a throwaway copy and cleans up after itself. `--session` also renders
  session states by starting a real session that blocks only the Socials websites, in
  the preview's browser companion. Add a snapshot state for any new UI.
- **The maintainer tries changes by hand:** `./build.sh preview && python3
  scripts/install-preview.py` (it prints the branch it installed), then open
  `/Applications/Ortus Preview.app`. Tell them which branch is installed. Previews never
  check for updates, so update flows can only be tried after a release.

**Leave nothing behind.**
- Quit anything you launch when you're done with it. Once your PR is merged, quit the
  preview: `osascript -e 'quit app "Ortus Preview"'`.
- Check what's running with `pgrep -fl "MacOS/Ortus$"`. Expect at most
  `/Applications/Ortus.app` and `/Applications/Ortus Preview.app`. A copy running from
  a workspace folder is a stray: tell the maintainer and quit it once no session holds
  it. Never kill a copy during a session.
- Throwaway runs use throwaway settings (`defaults delete <bundle id>` afterwards), and
  tests must not leave files in `~/Library`.
- If you find leftovers from other agents (stray copies, old builds, throwaway settings
  in `~/Library/Preferences`), list them for the maintainer instead of ignoring them.

## Pull requests: what the description covers

Every PR description is built around the change:

- **What changes**, in plain words.
- **Why**: the problem it solves or the goal it serves.
- **Who decided what.** For each meaningful choice, say whether a person (the
  maintainer, or whoever asked for the change) decided it or the agent chose it on
  its own, and why. Agent choices are the ones a reviewer most needs to check, so
  make them easy to find.
- **User experience impact, in its own section.** User experience is wider than the
  UI: how the app behaves, how and when it interrupts, notifies, blocks or asks for
  something, what it remembers, its defaults, timing and performance, and anything
  else that changes how it fits into someone's day. List every such change, even
  small ones, with who decided it and why. If nothing changes for users, say so.

## UI changes: show them in the PR

- A PR that changes what people see or do (layout, styling, copy, states, flows)
  puts images in its description: before and after, plus dark and light mode
  when colours change.
- Prefer real renders. On a Mac, use the snapshot harness and add a snapshot state
  for the new UI if none shows it. For the browser extension and landing page,
  screenshot the real pages with Playwright.
- If the app can't run (no macOS or Xcode), build an HTML mock-up at real size from
  the `OrtusTheme` tokens and render it with Playwright at 2x. Label it as a
  mock-up, not a render of the app.
- Keep images off the PR branch so they never land on `main`. Commit them to the
  `pr-assets` branch (an orphan branch; create it if missing) in a folder named
  after the PR branch, and link them as
  `https://raw.githubusercontent.com/scandolo/Ortus/pr-assets/<pr-branch>/<name>.png`.

## Teaching and problems in the UI

How Ortus explains itself. Five rules for anything that teaches, warns or asks for
a commitment:

1. **One surface, one job.** First decide if a message teaches, reports a problem or
   confirms a commitment. Never mix them in one view.
2. **Teach in the moment, with the user's own stuff.** Once, when it first matters,
   as visual as possible: their apps, their minutes, their end time, not generic
   copy. Then let the product repeat the lesson (the grace countdown) and keep it
   findable later.
3. **Problems live where they bite.** Next to what they break, until fixed, saying
   the consequence, with one verb + noun fix. Take over the main action only if the
   problem would spoil it. Say it once. Problems come before teaching.
4. **Honest commitments.** Before a lock, say what's blocked, for how long, and the
   one way out. Prefer undo (the grace window) to more confirmations; buttons name
   the outcome.
5. **Close the loop.** When someone fixes something, Ortus notices and moves on by
   itself. Activation is a first session that really blocks something, not a
   finished tour.

## Marketing and distribution

- For marketing and distribution work (positioning, landing page copy, SEO, launch
  posts, store listings, onboarding and activation, pricing, email), use the skills
  from [coreyhaines31/marketingskills](https://github.com/coreyhaines31/marketingskills).
  If your agent doesn't have them, install them with
  `npx skills add coreyhaines31/marketingskills` into `.claude/skills/` (git-ignored).
- The skills share a product marketing context doc, by default
  `.agents/product-marketing.md`. In Ortus it lives with the other private notes:
  use `.context/product-marketing.md`, built from the positioning brief and research
  already in `.context/plans/` and `.context/research/`. Don't create `.agents/`.

## Private notes

`.context/` is git-ignored and copied into each Conductor workspace from the
maintainer's master copy. It holds plans, research, design explorations, feedback and
screenshot tools (start with `.context/README.md`). It may not exist on other
machines. Never commit anything from it.
