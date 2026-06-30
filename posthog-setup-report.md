# PostHog post-wizard report

The wizard has completed a PostHog analytics integration for Ortus. PostHog was already partially wired (SDK installed, `Analytics.swift` wrapper, 5 events), so this run activated analytics by replacing the placeholder API key with the real project token and US-cloud host, then extended coverage with 7 new events across focus management, Slack, and AI chat.

## Events instrumented

| Event | Description | File |
|-------|-------------|------|
| `app_launched` *(existing)* | App opened; includes app version property | `Ortus/OrtusApp.swift` |
| `focus_started` *(existing)* | Focus session begun; `scheduled: Bool` property | `Ortus/Services/FocusManager.swift` |
| `focus_ended` *(existing)* | Focus session ended normally | `Ortus/Services/FocusManager.swift` |
| `focus_emergency_ended` *(existing)* | User spent their once-per-week emergency end | `Ortus/Services/FocusManager.swift` |
| `slack_connected` *(existing)* | OAuth flow completed successfully | `Ortus/Services/SlackOAuthService.swift` |
| `focus_reverted` | Session cancelled during the 30-second grace period | `Ortus/Services/FocusManager.swift` |
| `focus_extended` | User added time; `seconds_added: Int` property | `Ortus/Services/FocusManager.swift` |
| `schedule_added` | New recurring schedule saved; `days_count: Int` property | `Ortus/Services/FocusManager.swift` |
| `schedule_deleted` | Recurring schedule removed | `Ortus/Services/FocusManager.swift` |
| `slack_disconnected` | User disconnected their Slack workspace | `Ortus/Services/SlackOAuthService.swift` |
| `chat_message_sent` | Message sent to Claude AI; `is_first_message: Bool` property | `Ortus/Services/ClaudeCodeService.swift` |
| `chat_cleared` | Conversation cleared; `message_count: Int` property | `Ortus/Services/ClaudeCodeService.swift` |

## Next steps

A dashboard and insights have been created in PostHog to track Ortus usage:

- [Analytics basics (wizard) dashboard](https://us.posthog.com/project/489962/dashboard/1772072)
- [Focus sessions over time](https://us.posthog.com/project/489962/insights/IR2hkZX0)
- [Emergency ends (last 30 days)](https://us.posthog.com/project/489962/insights/SyRIUmFw)
- [Active users (DAU)](https://us.posthog.com/project/489962/insights/bMpOYRn8)
- [Slack integration rate](https://us.posthog.com/project/489962/insights/uFipQPtY)
- [AI chat usage](https://us.posthog.com/project/489962/insights/vLDCuXY3)

## Verify before merging

- [ ] Run a full production build (the wizard only verified the files it touched) and fix any lint or type errors introduced by the generated code.
- [ ] Run the test suite — call sites that were rewritten or instrumented may need updated mocks or fixtures.

### Agent skill

We've left an agent skill folder in your project at `.claude/skills/integration-swift/`. You can use this context for further agent development when using Claude Code. This will help ensure the model provides the most up-to-date approaches for integrating PostHog.
