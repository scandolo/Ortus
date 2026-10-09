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

## Checks

- Build: `swift build`, or `./build.sh` for a bundled `Ortus.app`
- Core checks: `swift run OrtusCoreChecks`
- Extension tests: `cd BrowserExtension && npm test` (needs Node)
- UI: debug builds render every panel state offscreen when launched with
  `ORTUS_SNAPSHOT_DIR=/path` (`Ortus/Debug/SnapshotHarness.swift`). Design rules
  live at the top of `Ortus/Views/OrtusTheme.swift`.

## Private notes

`.context/` is git-ignored and copied into each Conductor workspace from the
maintainer's master copy. It holds plans, research, design explorations, feedback and
screenshot tools (start with `.context/README.md`). It may not exist on other
machines. Never commit anything from it.
