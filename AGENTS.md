# Notes for coding agents

`CLAUDE.md` is a symlink to this file. For what Ortus is and how the code is laid
out, read `README.md`. This repo is public.

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

- Build: `swift build`, or `./build.sh` for a bundled `Ortus.app`
- Core checks: `swift run OrtusCoreChecks`
- Extension tests: `cd BrowserExtension && npm test` (needs Node)
- UI: debug builds render every panel state offscreen when launched with
  `ORTUS_SNAPSHOT_DIR=/path` (`Ortus/Debug/SnapshotHarness.swift`). Design rules
  live at the top of `Ortus/Views/OrtusTheme.swift`.

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

## Marketing and distribution

- For marketing and distribution work (positioning, landing page copy, SEO, launch
  posts, store listings, onboarding and activation, pricing, email), use the skills
  from [coreyhaines31/marketingskills](https://github.com/coreyhaines31/marketingskills).
  If your agent doesn't have them, install them with
  `npx skills add coreyhaines31/marketingskills`. They land in `.claude/skills/` or
  `.agents/skills/`, and both folders are git-ignored.
- Start with `product-marketing`: the other skills read its context doc,
  `.agents/product-marketing.md`. Draft that doc from the plans and research in
  `.context/`, and keep it out of git, since this repo is public.

## Private notes

`.context/` is git-ignored and copied into each Conductor workspace from the
maintainer's master copy. It holds plans, research, design explorations, feedback and
screenshot tools (start with `.context/README.md`). It may not exist on other
machines. Never commit anything from it.
