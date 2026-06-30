# Ortus Launch Strategy

**Status:** Working draft, post office-hours synthesis
**Date:** 2026-06-29
**Branch:** ortus-launch-office-hours
**Source:** Synthesizes the office-hours session (`office-hours-transcript-2026-06-19.md`) plus follow-up discussion on Slack attribution and distribution.

---

## 1. One-line thesis

Ortus removes the inputs and holds the wall. It is the layer that lets a maker disappear from real-time comms and do their best work, and the user's own AI can stand guard over what they left behind.

It does not mute Slack. It kills it.

---

## 2. Product

A macOS menu bar app that, during focus hours:

- Terminates Slack (not mute, not DND) and blocks relaunch and Cmd+Q.
- Has no "End Focus" button. The only exit is an emergency end, rate-limited to once per calendar week.
- Auto-sets Slack profile status and DND on entry, clears on exit.
- Offers an optional AI chat over Slack via a local Claude Code subprocess, so the user can query what they left behind without reopening the app and falling into the rabbit hole.

The category is not "focus app that blocks distractions." It is "willpower replacement for people who already know their willpower loses."

---

## 3. ICP (locked)

**Makers whose self-worth and career both run through deep work, and who know their willpower fails.**

- Roles: engineers, growth, designers, founders. People whose output comes from focused creation, not meetings.
- The defining psychographic: self-aware-distractible. They have tried Slack DND, "I'll check at 11," macOS Focus modes, and watched all of them fail because they open Slack "for one quick thing" and lose an hour.
- Disciplined people are explicitly **not** the ICP. DND is enough for them.

**Why this ICP, in their words (from the session):**
1. Losing a focus morning makes them feel like a failure: "the day goes by and you got nothing important done."
2. They get fulfillment from focused creation, from doing their best work.
3. Focus compounds into competence, skills, promotions, reputation. Lost focus compounds the other way.

This is also Federico's own tribe, which makes it the easiest first market to reach.

**Demand evidence today:** n=1 active user (Federico). Several colleagues have asked to have it shared with them, unprompted. That is genuine interest but not yet validated demand, because "asked to share" costs them nothing and there is currently no frictionless way for them to say yes.

---

## 4. Positioning (locked)

- **Emotional register, not productivity.** Most focus apps sell "get more done." Ortus sells relief from self-disappointment. Landing-page well to draw from: *"Stop going to bed feeling like you got nothing that mattered done."* Do not let this get sanded into "Boost your focus today."
- **No anti-AI villain.** Earlier framing ("Ortus is the anti-AI, every tool wants your attention") was rejected and corrected. AI (Claude specifically) is useful because it is useful, not because it traps attention. The correct frame: AI is the **ally that makes it safe to disconnect**. The enemy is the always-on, real-time nature of comms tools that shred focus, not AI.
- **The hook:** "Ortus doesn't mute Slack. It kills it. No End Focus button. Emergency exit once a week." Provocative, screenshot-able, true.

---

## 5. The architecture truth that shapes everything

There are three ways to give Ortus low-friction AI-over-Slack. The office-hours research established that **all three are built on sand for a paid, company-targeting product:**

1. **Claude Code subprocess (current approach).** As of **June 15, 2026** (now ~2 weeks live), Anthropic meters non-interactive / headless `claude -p` usage and third-party apps authenticating with a subscription against a separate, fixed, non-rollover **Agent SDK credit pool** ($20/mo Pro, $100 Max 5x, $200 Max 20x), billed at API rates. Not banned (Claude Code is the official exempt tool, on the user's own machine, own subscription), but metered and capped on the user's side. Cannot be the foundation of a paid product.
2. **Browser session tokens (xoxc / xoxd).** Reads Slack with no app to publish and no admin approval, inheriting the user's own logged-in session. But: grey-area vs Slack ToS, invisible to admins (which is exactly what a security team treats as exfiltration), and tokens expire. A compliance landmine for the exact ICP (engineers at real companies).
3. **Publish our own Slack app.** Clean and legit, but every user on a Teams/Enterprise plan hits **admin approval** on install. For a bottoms-up maker product, that wall is death.

**Conclusion (locked):** The AI/Slack layer is **not the product and not what we monetize.** It is a free, opt-in, bring-your-own, explicitly-labeled "advanced" bonus that rides on whatever the user already has.

The product is the part that is 100% local, zero-dependency, zero-ToS-risk, zero-marginal-cost, and structurally un-meterable by Anthropic or Slack: **the focus enforcement.**

On the "via Claude" attribution question: that footer is Slack rendering the `app_id` stamped on a message by whichever OAuth app issued the token. It is not a field we can override or spoof, and reusing Anthropic's token is a ToS bomb. This reinforces the same conclusion: do not try to be the Slack-sending layer.

---

## 6. Business model (decided direction)

**Free v1 from day 0**, shipping both:
- The local focus enforcement core (the real product), and
- The Claude Code chat feature, **free**, as a bring-your-own-Claude-Code power-user bonus. (This is Federico's explicit decision: spread the chat-enabled version free from day one. It works great for users who already have Claude Code + Slack MCP, degrades gracefully for those who do not.)

No backend, no published Slack app, no pricing page at launch. This deletes every hard architecture problem at once and gets real users in-hand this week.

**Money comes later, and not from the AI.** The eventual paid layer is the **workflow layer that changes how a maker works**, none of which carries marginal cost or ToS risk:
- Block *all* inputs, not just Slack (email, Teams, notifications).
- Focus analytics tied to what you actually shipped.
- Post-session triage: a clean "here is what you missed, triaged" on the way *out* of a session (never mid-focus, which would smuggle Slack back in and violate the soul of the product).
- Deeper local automations and customization.

**Pricing:** parked, intentionally. The category supports a premium tier ($12/mo opening, $20/mo as a destination, comparable to Sunsama / Rize / Superhuman) *if* positioned as an identity tool rather than a cheap blocker. But we validate retention before charging. Federico wants to charge on value, not cost-plus, and does not want a number yet.

**Sequencing (recommended):**
- **Now, Play 1:** Free, spread it, validate that non-Federico people keep it open every morning.
- **Next, Play 2:** Individual Pro = the workflow layer above. Design it now, ship it once retention is proven.
- **Later, Play 3:** Teams / focus-culture tier (coordinated, enforced focus hours across a squad). Higher ACV, value-based pricing, but pulls toward B2B motion. Trigger only if teams cluster organically. Note: because Ortus is local with zero Slack-data exfiltration, the IT/admin conversation here is "it kills an app on the laptop," not "it reads our Slack on a server," which is far milder than the Slack-app path.

---

## 7. Distribution / GTM

**Beachhead:** Federico's own tribe first. The colleagues who already asked, then their networks. Goal: get Ortus into 5 non-Federico hands this week.

**The shareability gate (do first, it is table stakes):** a signed and notarized `.dmg` that installs by double-click and drag-to-Applications. No build-from-source, no Xcode tools, no Gatekeeper warning. Requires the $99/yr Apple Developer account. This is the single thing standing between "I'd love that" and an actual install.

**Channels:**
- Show HN: "Show HN: Ortus, it doesn't mute Slack, it kills it."
- r/macapps, r/productivity.
- Build-in-public on X (start before launch, not the day of).
- Product Hunt once there are testimonials.
- Maker / indie communities.

**Why it spreads:** the kill-not-mute, no-end-button, once-a-week-escape mechanic is provocative and screenshot-friendly. Makers share willpower hacks. The emotional positioning ("stop feeling like a failure at end of day") resonates in the exact communities the ICP lives in.

---

## 8. v1 cut line (what ships free, day 0)

In:
- Local focus enforcement: kill Slack, block relaunch + Cmd+Q, scheduling, status + DND sync, emergency end (once per calendar week), grace period.
- Claude Code chat over Slack, free, BYO, labeled "Advanced." Graceful messaging for users without Claude Code installed.
- Signed + notarized `.dmg` distribution.
- Auto-update (Sparkle).
- Anonymous, opt-out analytics (PostHog) to measure activation and retention from day one.
- Crash reporting (Sentry).

Out (deferred to paid layer or later):
- All-inputs blocking beyond Slack.
- Focus analytics tied to shipped work.
- Post-session triage / exit brief.
- Any pricing page or payment.
- Teams features.
- Windows.

---

## 9. What still needs to be defined

**Product / activation:**
- The BYO-Claude-Code activation flow. How do we wrap "connect Claude Code + Slack MCP" so it feels like an Ortus onboarding step rather than a power-user setup chore? What is the exact graceful-degradation experience for the (majority) of users who do not have it?
- Definition of an "activated" user and the core retention metric. What counts as a kept user (e.g. opens a focus session N mornings per week)?
- Is the post-session exit brief in v1 free, or held for the paid layer? (Leaning: simple version could be a free hook, rich version paid.)

**Business model:**
- The precise free / paid cut line for the eventual Pro tier.
- The exact Pro feature set (what specifically is the "workflow layer").
- Pricing model and number (subscription assumed, validate after retention).
- Evidence of willingness to pay: has anyone actually signaled money, or is it free-until-proven? (Currently: free-until-proven.)

**Distribution / brand:**
- Domain and final name check (ortusapp.com or similar).
- Landing page build, demo video (45 to 90s, captioned), screenshots.
- Privacy policy + ToS (must explicitly state Ortus does not store Slack messages or tokens on a server, because the local-first story is the trust differentiator).
- Support email.
- Pre-launch email list for early-access capture.

**Operations / risk:**
- Apple Developer account purchase and notarization pipeline verified on a clean machine.
- Anthropic ToS / metering monitoring. The BYO Claude Code feature is a dependency Anthropic just attached a meter to; watch for further changes. Have a fallback (BYO API key behind a flag) designed but not shipped.
- Legal entity (UK vs US considerations).
- macOS-only caps TAM; revisit Windows around month 6 if traction is real.

**Open strategic question:**
- "Why not just Claude Desktop / a Claude skill?" will come up in every HN thread. The answer is the focus enforcement and the philosophy (no inputs, hold the wall), not the AI. Sharpen a clean two-sentence response that does not trash Anthropic.

---

## 10. Immediate next steps (this week)

1. Buy the Apple Developer account ($99/yr). No debate.
2. Produce a signed + notarized `.dmg`. Verify Gatekeeper-clean install on a machine that is not Federico's.
3. Hand it to the 5 colleagues who asked. Watch them install. Every place they get stuck is a fix before any public launch.
4. Wire PostHog activation + retention events and Sentry crash reporting before step 3, so the 5 installs produce signal.
5. Draft the landing page from the locked positioning (headline well from section 4).

The bar to clear before spending a day on distribution: do the 5 non-Federico users keep opening it every morning? Retention first, then funnel, then scale.
