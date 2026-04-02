# Slack Install Flow

## What Ortus is doing today

Ortus is a macOS menu bar app that blocks Slack during focus sessions and optionally lets the user ask Claude questions about their Slack workspace without reopening Slack.

Today, the Slack connection flow is fully manual:

1. The user creates their own Slack app.
2. The user copies the app's client ID and client secret into Ortus.
3. Ortus starts a loopback OAuth flow on `http://127.0.0.1:<port>/callback`.
4. Ortus exchanges the OAuth code with `oauth.v2.access` and stores the user token in Keychain.

That works for development, but it is not a shippable consumer UX.

## What "one-click" really means

For a user's first connection, true one-click is not realistic because Slack still needs to show a consent/install screen. The practical target is a two-step flow:

1. Click `Connect Slack` in Ortus.
2. Click `Allow` in Slack.

Once the app is already installed for that workspace, the reconnect flow can feel close to one click.

## Best path forward

The best product path is to move from "every user creates an app" to "Ortus owns one Slack app":

1. Create a single Ortus Slack app owned by the team.
2. Define its scopes with a manifest in-repo.
3. Enable Slack distribution for that app.
4. Use a shared install URL from Ortus instead of asking for per-user credentials.
5. Use Slack's user-token-only OAuth flow with PKCE so the desktop app does not ship a client secret.
6. Redirect back into the macOS app through a custom URL scheme after Slack finishes the browser step.

## Important constraint

The current app uses a local loopback redirect, but the distributed install flow should be treated as a hosted-redirect flow:

- Slack distribution expects a configured redirect URL on the app we own.
- The desktop app should not ship the Slack client secret.
- PKCE solves the secret problem, but not the redirect-hosting problem.

That means we likely need a tiny hosted callback page such as `https://auth.ortus.app/slack/callback` that immediately redirects to something like `ortus://slack-oauth?...`.

## Recommended architecture

### Production install flow

1. User clicks `Connect Slack` in Ortus.
2. Ortus opens Slack's OAuth authorize URL using the shared Ortus app's client ID.
3. Ortus sends `user_scope=...`, a `state`, and a PKCE `code_challenge`.
4. Slack redirects to the hosted HTTPS callback.
5. The hosted callback redirects to `ortus://slack-oauth?code=...&state=...`.
6. Ortus receives that URL, validates `state`, and exchanges the code with `oauth.v2.user.access`.
7. Ortus stores the returned user token in Keychain and confirms the workspace with `auth.test`.

### Development fallback

Keep the current manual client ID/client secret + loopback flow as a developer fallback until the shared app is fully provisioned.

## Why this is the right compromise

- Better UX: users install the Ortus app, not their own Slack app.
- Better security: no client secret embedded in the desktop binary.
- Better operations: one manifest controls scopes and redirect URLs.
- Better supportability: permission changes happen in one Slack app instead of per-user setup.

## What this branch adds

- A Slack manifest template at [config/slack-app-manifest.yaml](/Users/federico/fyxer/other/Ortus/config/slack-app-manifest.yaml)
- App-side support for a bundled Slack app install mode
- PKCE scaffolding for Slack's user-token-only exchange
- A custom URL callback entry point in the macOS app
- Preservation of the current manual flow as fallback

## Open decisions

1. Whether the shared Slack app should be public-distribution or a private app we control for a smaller rollout.
2. Where to host the HTTPS callback page.
3. Whether to keep the manual fallback visible in production or hide it behind developer mode.
4. Whether token rotation should be enabled on the Slack app before launch.

## Official references

- Installing with OAuth: https://api.slack.com/authentication/oauth-v2
- `oauth.v2.user.access`: https://docs.slack.dev/reference/methods/oauth.v2.user.access/
- `oauth.v2.access`: https://docs.slack.dev/reference/methods/oauth.v2.access/
- Deep linking into Slack: https://docs.slack.dev/interactivity/deep-linking/
