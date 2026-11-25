# Agent setup and Codex: mock-ups

Mock-ups, not renders of the app. Built at the panel's real size (420 x 560 pt) from the
`OrtusTheme` tokens and the bundled Archivo fonts, rendered at 2x with Playwright.

To re-render: copy `Ortus/Fonts/*.woff2` into a `FONTS/` folder next to `mockups.html`,
install `playwright-core`, and run `node render.mjs` (it writes `out/<frame>.png`).
`render.mjs` points at a cached Chromium for Testing; change `exe` to yours.
