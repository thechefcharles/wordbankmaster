# WordBank — iOS Launch Roadmap

**Goal (now):** get WordBank from a SvelteKit/Vercel web app **onto TestFlight in
front of real test users**, as fast as is sensible. Full App Store submission,
the sweepstakes prize, and the LLC/entity work are **deferred** until after we're
learning from testers (see *Deferred* at the bottom).

**Status legend:** ✅ done · 🔄 doing · ⬜ todo · 🔒 blocked/needs decision
**Living doc** — check items off as we ship; keep notes inline.

---

## 🎯 Critical path to first TestFlight (the only thing that matters right now)
1. Capacitor wrapper + a bundle-able **static/SPA build** of the front-end.
2. **Auth that works in the bundled app for testers** — v1 = **email + password
   only** (works client-side against Supabase, no web redirects). Hide Google +
   the web reset-link flow in the native build for now. *(This avoids the whole
   OAuth/deep-link rework AND the Sign in with Apple requirement — those are only
   triggered by offering third-party social login, which v1 won't.)*
3. App icon + launch screen + bundle id.
4. Build in Xcode → upload to App Store Connect → **Internal TestFlight** (up to
   100 testers, **no review**, available as soon as the build processes).
5. Optional next: **External TestFlight** (up to 10k) — needs a lighter Beta App
   Review (privacy policy URL + basic compliance), so do it once the basics land.

Everything not on this list is intentionally *after* we have testers.

### Engagement features shipped (Duolingo-inspired)
- [x] **Streak screen** (`/streak`) + menu flame chip.
- [x] **Daily Quests** (`/quests`) — 3 deterministic quests/day (same for everyone),
      progress from the events table (no engine changes), finish all 3 → claim a
      streak freeze. Menu card shows progress. (`supabase-quests.sql`.)
- [x] **Friends Daily leaderboard** (`/leaderboard` Friends tab) — shareable
      friend code, add by code or `?add=CODE` invite link, you-vs-friends ranking
      on today's Daily. (`supabase-friends.sql`.) Stepping stone to leagues.
- [ ] Next candidates: pressure/blitz mode (user-requested) · leagues/divisions
      (needs players + sweepstakes lock) · cosmetic currency + shop · profile
      screen · push notification (native).

### Zero-friction testing (no TestFlight needed)
WordBank is a live website, so the lowest-friction way to get friends testing is
just the **URL** — no app stores, no TestFlight, no downloads:
`https://wordbanksvelte.vercel.app`. It's a polished **PWA** (manifest +
apple-touch-icon + standalone meta), so "Share → Add to Home Screen" gives a
real WordBank icon that opens full-screen. Same accounts/leaderboard as native.
TestFlight is for the *App Store* track + native features (push), not a
prerequisite for feedback.

---

## Where we are
- ✅ Web app feature-complete enough to test (daily, arcade survival, free play,
  badges, leaderboard, 720 puzzles, auth + password reset working on web).
- ✅ Apple Developer Program account exists (Individual is fine for TestFlight —
  no entity/LLC decision needed yet).
- ⬜ Everything below.

**The core reality:** Apple won't accept a plain web link / thin PWA (Guideline
4.2). We wrap the front-end in **Capacitor** (native shell, bundled UI, native
APIs). For v1 we sidestep the hardest part (native OAuth/deep-link auth) by
shipping **email/password only**.

---

## Phase 0 — Foundations (light; don't block on these)
- [x] Apple Developer Program enrollment ($99/yr).
- [ ] Reserve the app name in App Store Connect; pick bundle id
      (e.g. `com.wordbank.app`).
- [x] **Analytics** — first-party event pipeline (`supabase-analytics.sql`
      `events` table + `log_event` RPC; client `src/lib/analytics.js` `track()`).
      Instruments app_open / signup / login / daily_start / daily_result /
      arcade_start / arcade_solve / arcade_over / freeplay_start. KPI queries in
      the SQL file; queryable via the Supabase service role.
- [ ] *(optional)* **Crash/error reporting** — Sentry.
- [ ] ~~Entity / LLC decision~~ → **deferred** (Individual account covers TestFlight).

## Phase 1 — Native shell to get a testable build 🔄
- [x] **Capacitor wrapper added** — `@capacitor/core` + `ios` + `cli`,
      `capacitor.config.json`, generated `ios/` Xcode project (SPM, no CocoaPods).
- [x] **v1 load strategy = remote URL.** `server.url` points the native app at the
      live site (`wordbanksvelte.vercel.app`). Zero auth rework, instant iteration
      (web deploys reflect in the app with no resubmit), testers use the real app.
      `www/index.html` is the offline fallback. *Tradeoff:* Apple discourages
      pure-remote apps for the PUBLIC store (4.2) → **convert to a bundled build +
      native auth before public submission** (deferred item below). Fine for
      TestFlight.
- [x] **v1 auth = email + password** — works in the webview with no redirects.
      *(Google OAuth inside a webview is unreliable; testers use email/password.
      Native Google + Sign in with Apple are deferred to the bundled build.)*
- [ ] **Signing + first run** (you, in Xcode): `npm run cap:open` → select your
      Team under Signing & Capabilities → run on a simulator/device.
- [x] **App icon + launch screen** = WordBank coin on dark bg (generated from
      `static/logo-mark.png` via `scripts/make-ios-assets.cjs` + `@capacitor/assets`).
      Home-screen label `CFBundleDisplayName` = WordBank. Regenerate with
      `node scripts/make-ios-assets.cjs && npx capacitor-assets generate --ios`.
- [ ] App Store Connect: create the app record; **Archive → upload** for TestFlight.

### How to build & test the iOS app
```bash
npm run cap:sync      # copy config/web-assets into the iOS project (run after config changes)
npm run cap:open      # open ios/App in Xcode
```
In Xcode: **App target → Signing & Capabilities → Team** = your Apple Developer
team (this sets the provisioning automatically). Bundle id is `com.wordbank.app`
(change in `capacitor.config.json` *and* Xcode if you want a different one; then
`npm run cap:sync`).
- **Run on simulator/device:** pick a destination, press ▶.
- **Ship to TestFlight:** Product → Destination = *Any iOS Device*, then
  **Product → Archive** → Distribute App → App Store Connect → Upload. The build
  appears in App Store Connect → TestFlight after processing; add Internal testers.

## Phase 2 — TestFlight (the goal)
- [x] **Internal testing REACHED** (2026-06-24) — Build 1 v1.0 status "Testing" in
      App Store Connect; 1 install / sessions logged. App name = "WordBank Daily".
- [ ] **Internal testing** — add testers by Apple ID (up to 100); available right
      after the build processes, **no review**. ← first real test users land here.
- [ ] **External testing** — up to 10,000; needs a lighter **Beta App Review**
      (privacy policy URL + basics). Do once Phase 1 is solid.
- [ ] Tester feedback channel (TestFlight feedback + a simple form/Discord).
- [ ] Watch activation + D1/D7 retention; iterate.

---

## ⏸️ Deferred — after we have test users (do NOT block TestFlight on these)
*Pulled out of the critical path per decision (2026-06): get to testers first.*

**Store-submission compliance** (needed for public App Store, not for TestFlight):
- [ ] **Re-enable Supabase email confirmation** before public launch (turned OFF
      2026-06 for frictionless beta signup). Critical before the sweepstakes —
      verified emails = anti-fraud + account recovery + prize eligibility.
- [ ] **Sign in with Apple** — required *if/when* we re-add Google or other social login. [4.8]
- [ ] **In-app account deletion** — required for sign-up apps. [5.1.1(v)] Flow +
      server RPC purging profile/sessions/results.
- [x] **Privacy policy page** at `/privacy` (→ `https://wordbanksvelte.vercel.app/privacy`;
      needed for external TestFlight). Still TODO: enter the URL in App Store Connect
      + fill the App Privacy nutrition label.
- [ ] **Age rating**, **Support URL**, screenshots, description, keywords.
- [x] **Streak screen** (`/streak`) — Duolingo-style flame + current/longest +
      "N days from your best" nudge + month calendar heatmap of daily wins/misses;
      tappable streak chip on the menu. (`get_streak_overview` RPC.)
- [ ] **Push notifications** ("daily ready") — big retention lever + native value;
      the other half of the streak loop. Needs native APNs (bundled build). [4.2]
- [ ] Native auth rework: native Google + password-reset deep-linking (custom URL
      scheme / universal links).
- [ ] Full **App Review** pass.

**Entity / business** (deferred):
- [ ] LLC vs Individual + Organization Apple account (D-U-N-S). Only needed before
      real prizes/payouts; Individual covers TestFlight.

**~~Sweepstakes prize system~~ — DROPPED (2026-06).** Replaced by the bank
economy + friend wagering — see **BANK_ECONOMY.md**. (No real-money prize draw,
so no Official Rules / state registration / 18+ gate needed for that reason.)
The sweepstakes design notes below are kept only for history.

---

## Compliance checklist (for PUBLIC App Store submission — not TestFlight)
*Internal TestFlight needs none of these; external TestFlight needs a privacy
policy + basics. Full list kept here for when we submit publicly.*
- [ ] Sign in with Apple — only if we re-add Google / social login. [4.8]
- [ ] In-app account deletion. [5.1.1(v)]
- [ ] Privacy policy + accurate App Privacy label. [5.1.1]
- [ ] App feels native / adds value beyond a website (push, etc.). [4.2]
- [ ] If sweepstakes in-build: Official Rules linked, Apple not the sponsor, no
      paid-IAP entry, 18+. [5.3]
- [ ] No real-money purchase that improves leaderboard rank (see sweepstakes trap).

---

## 🚀 App Store Submission Pack (when ready to go public)
*TestFlight build is live (Build 1 "Testing", internal + Friends & Family). This is
the pack for the **public** Distribution submission. Approval risk is LOW — WordBank
is a virtual-currency word game with **no real money** (see `wordbank-virtual-currency`
memory) — but there are a few hard requirements Apple rejects without.*

### ⛔ Hard blockers (fix BEFORE submitting — these cause automatic rejection)
- [ ] **In-app account deletion** [5.1.1(v)] — **NOT built yet.** Apps with account
      creation MUST let users delete their account *in-app* (not just "email us").
      Needs: a "Delete account" button (Profile/Settings) → confirm → server RPC that
      purges profile + auth user + their rows. Single biggest rejection risk for us.
- [ ] **Demo account** in App Review Information — the app is login-gated, so review
      WILL fail without working credentials (and a 2nd account or a video for
      challenges, which need two players).
- [ ] **Sign in with Apple** [4.8] — the app offers **Google** login, which *requires*
      Sign in with Apple to also be offered (equivalent placement). Apple ID infra is
      live (Services ID `app.wordbank.signin`) — **verify the button is actually wired
      into the native Auth UI**, or remove Google from the native build.
- [ ] **Real native build, not a remote-URL wrapper** [4.2] — the TestFlight build
      points `server.url` at the live website. Apple often rejects thin web wrappers
      for the public store. Convert to a **bundled** build (and ideally native auth)
      before public submission, or be ready to argue native value (offline fallback,
      push, etc.).

### Required metadata / settings
- [ ] Privacy policy URL entered (`/privacy`) **+ App Privacy "nutrition label"** filled
      (we collect email, gameplay/analytics, social graph). [5.1.1]
- [ ] Screenshots — 6.7" (required) + 6.5"; iPad set only if iPad-supported.
- [ ] App name / subtitle / description / keywords / promo text; Category = Games ›
      Word (or Puzzle); Support URL; copyright; contact.
- [ ] **Age rating** questionnaire — answer honestly; virtual "buy-in/wager" framing
      *may* trip the **Simulated Gambling** descriptor (→ 17+). Not a rejection, just
      rate it correctly.
- [ ] **Export compliance** — standard HTTPS only → answer "no" to non-exempt
      encryption (set `ITSAppUsesNonExemptEncryption=false` to skip the prompt).
- [ ] On submit, choose **"Manually release this version"** so approval doesn't
      auto-publish — you press go when ready.

### 📝 Reviewer note (paste into App Review Information → Notes)
```
WordBank is a word-puzzle game. A few clarifications to speed review:

• ALL CURRENCY IS VIRTUAL. The "$", "Cash", "Bankroll", "buy-in", "pot", and
  "cash out" are an in-game points economy shown in dollars for THEME ONLY.
  There are NO real-money transactions, NO in-app purchases, NO deposits, and
  NO payouts of any kind. New accounts simply start with a virtual balance.
  Nothing in the app charges or pays real money.

• Not gambling: "challenges" are friendly word-puzzle competitions scored in
  virtual points. Nothing of real-world value is staked, won, or withdrawn.

• Login is required. Demo account:
      username: <DEMO_USER>   password: <DEMO_PASS>
  (Sign in with Apple also works.)

• A 1-on-1 / group challenge needs two players. Second test account:
      username: <DEMO_USER_2>  password: <DEMO_PASS_2>
  (Happy to provide a screen recording if helpful.)

• Account deletion: Profile → Settings → Delete Account.

Thank you!
```
*(Create two throwaway demo accounts and drop their creds in before submitting.
Keep the note in sync if flows move. I can generate the demo accounts on request.)*

---

## Data & KPIs (instrument before testers)
**Tooling:** PostHog or Supabase `events` table; Sentry; Apple App Analytics (free, once on store).

Track:
- **Activation:** signup conversion · % completing first daily · first arcade run.
- **Retention (the make-or-break number):** D1 / D7 / D30 · DAU/WAU/MAU · stickiness (DAU/MAU).
- **Engagement:** daily completion rate · arcade runs/user · session length · sessions/day · streak distribution.
- **Funnel** drop-offs · **crash-free rate**.
- **Leaderboard integrity:** suspected-cheat rate · multi-account signals.

---

## Sweepstakes (deferred design — build later, lawyer-review required)
> ⏸️ **Deferred** (2026-06): not in the path to test users. Captured so we don't
> lose the design. ⚠️ Not legal advice — Official Rules must be reviewed by a
> promotions attorney before any prize goes out.

**Concept:** monthly gift card to a **randomly drawn winner from the top 10**
leaderboard (skill to qualify + chance to win).

**The legal core:** an illegal lottery = **prize + chance + consideration**. The
random draw keeps *chance*, so we must remove **consideration** → a true sweepstakes:
- [ ] **No purchase necessary, and purchases must not improve odds.** ⚠️ THE TRAP:
      if anyone can ever **pay real money for anything that raises leaderboard
      rank**, that's consideration → illegal lottery. Keep ranking-affecting
      items non-purchasable, OR add a **free Alternative Method of Entry (AMOE)**.
      *(Today power-ups are earned, not bought — preserve that.)*
- [ ] **Official Rules:** sponsor, eligibility, entry window, drawing method +
      odds, prize ARV, winner notification, publicity/liability release, disputes, privacy.
- [ ] **Eligibility:** 18+, US-only to start, "void where prohibited."
- [ ] **Keep prize value modest** (e.g. $50–$100 gift card) to stay under state
      registration/bonding thresholds (NY/FL bond > $5,000; RI > $500).
- [ ] **Winner verification + W-9 / 1099** if a winner hits $600/yr.
- [ ] **Anti-fraud:** terms allow disqualification; manually verify the top 10
      before each draw; use existing anomaly-detection funcs; guard multi-accounting.
- [ ] **Apple [5.3]:** WordBank (the entity) is the Sponsor, not Apple; entry is
      never a paid IAP.
- [ ] **Engage a promotions attorney / service** before scaling prize value.

**Server work when we build it:** a `sweepstakes_draws` table + an admin-only
RPC that snapshots the eligible top-10 for the period and records the drawn
winner (auditable, deterministic seed stored).

---

## Open decisions 🔒 (none block the critical path)
1. **Analytics tool:** PostHog vs in-house Supabase `events` (optional before testers).
2. **App name + bundle id** for App Store Connect.
- *Deferred decisions* (entity/LLC, native Google + Sign in with Apple, sweepstakes
  timing, prize value, geo scope) intentionally parked until after we have testers.

## Notes / decisions log
- 2026-06: roadmap created. Apple Developer account already in hand.
- 2026-06: **decision — get to test users (TestFlight) first.** Sweepstakes, LLC/
  entity, and full store-compliance deferred. v1 native auth = **email/password
  only** (hide Google + web reset link in the native build) to skip the OAuth/
  deep-link rework and the Sign in with Apple requirement for v1.
