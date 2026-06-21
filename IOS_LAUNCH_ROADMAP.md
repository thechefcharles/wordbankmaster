# WordBank — iOS Launch Roadmap

**Goal:** get WordBank from a SvelteKit/Vercel web app to TestFlight, then the
real iOS App Store, with the data and legal structure to (eventually) run a
monthly sweepstakes prize.

**Status legend:** ✅ done · 🔄 doing · ⬜ todo · 🔒 blocked/needs decision
**Living doc** — check items off as we ship; keep notes inline.

> ⚠️ Not legal advice. The sweepstakes section is a framework only — the Official
> Rules must be reviewed by a promotions attorney before any prize goes out.

---

## Where we are
- ✅ Web app feature-complete enough to test (daily, arcade survival, free play,
  badges, leaderboard, 720 puzzles, auth + password reset working).
- ✅ Apple Developer Program account exists.
- ⬜ Everything below.

**The core reality:** Apple won't accept a plain web link / thin PWA (Guideline
4.2). We wrap the front-end in **Capacitor** (native shell, bundled UI, native
APIs). The biggest single task is **reworking auth for native** (the SSR routes
`/auth/callback` + `/auth/confirm` don't exist inside a bundled app).

---

## Phase 0 — Foundations (do now, in parallel)
- [x] Apple Developer Program enrollment ($99/yr).
- [ ] **Entity decision** 🔒 — Individual vs LLC + Organization account (needs a
      free D-U-N-S number, ~1–2 wks). LLC recommended before real prizes/payouts.
      Decide who the App Store "seller" + sweepstakes "Sponsor" is. *(see Open
      Decisions)*
- [ ] **Analytics** — wire PostHog (free tier) **or** a Supabase `events` table
      into the web app now, so we have baselines before testers. *(see Data & KPIs)*
- [ ] **Crash/error reporting** — Sentry (web now, native later).
- [ ] Reserve the app name in App Store Connect; pick bundle id
      (e.g. `com.<entity>.wordbank`).

## Phase 1 — Native shell + compliance must-haves
*(These are the items that otherwise get you rejected — front-load them.)*
- [ ] **Capacitor wrapper** — add Capacitor, produce a **static/SPA build** of the
      front-end (currently `adapter-vercel` SSR; need a bundle-able build), open
      in Xcode, run on a device.
- [ ] **Native auth rework** 🔒 — replace web OAuth redirects with native flow:
      Supabase + Capacitor, custom URL scheme / universal links for deep-linking
      back into the app. Decide: keep email/password + add native Google, or
      simplify.
- [ ] **Sign in with Apple** — REQUIRED because we offer Google login (Guideline
      4.8). Add it (or drop Google).
- [ ] **In-app account deletion** — REQUIRED for sign-up apps (5.1.1(v)). Add a
      "Delete my account" flow + a server RPC that purges profile/sessions/results.
- [ ] **Push notifications** — "your daily puzzle is ready" (APNs via Capacitor).
      Doubles as the #1 retention lever AND helps satisfy 4.2 "native value".
- [ ] Native polish: app icon, launch screen, safe-area insets, status bar,
      haptics (already have web haptics — verify on device).
- [ ] App Store Connect: create the app record, upload first build (Xcode/Transporter).

## Phase 2 — TestFlight
- [ ] **Internal testing** — add testers by Apple ID (up to 100); available right
      after build processes, no review.
- [ ] **External testing** — up to 10,000 testers; requires a (lighter) **Beta App
      Review**. Need: privacy policy URL, test notes, contact.
- [ ] Tester feedback channel (TestFlight feedback + a simple form/Discord).
- [ ] Watch the KPI dashboard; iterate on activation + D1/D7 retention.

## Phase 3 — App Store submission prep
- [ ] **Privacy policy** (hosted page) + **App Privacy nutrition label** in App
      Store Connect (email, gameplay, analytics, etc.).
- [ ] **Age rating** — set honestly; **18+ gate** once a sweepstakes exists.
- [ ] **Support URL** + marketing page, screenshots, description, keywords.
- [ ] Full **App Review** pass (4.2 functionality, 4.8 Sign in with Apple, 5.1.1
      account deletion, 5.3 if sweepstakes is in-build).
- [ ] Decide: ship the game **first**, turn the sweepstakes on later (less
      rejection surface), vs. include it at launch with proper rules.

## Phase 4 — Sweepstakes + launch
- [ ] Finalize sweepstakes (see section below) — entity, Official Rules, AMOE,
      18+ gate, anti-fraud, winner verification.
- [ ] Public launch.
- [ ] Run the first monthly draw; verify winner; issue gift card; 1099/W-9 if
      thresholds hit.

---

## Compliance checklist (rejection-risk — must all be true at submit)
- [ ] Sign in with Apple offered (because Google login exists). [4.8]
- [ ] In-app account deletion. [5.1.1(v)]
- [ ] Privacy policy + accurate App Privacy label. [5.1.1]
- [ ] App feels native / adds value beyond a website (push, etc.). [4.2]
- [ ] If sweepstakes in-build: Official Rules linked, Apple not the sponsor, no
      paid-IAP entry, 18+. [5.3]
- [ ] No real-money purchase that improves leaderboard rank (see sweepstakes trap).

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

## Sweepstakes prize system (framework — lawyer-review required)
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

## Open decisions 🔒
1. **Entity:** Individual (move now, convert later) vs LLC + Org account (liability
   shield, better Sponsor) — needed before real prizes.
2. **Analytics tool:** PostHog vs in-house Supabase `events`.
3. **Auth on native:** keep Google + add Sign in with Apple, vs Apple + email only.
4. **Sweepstakes at launch vs after** (rejection-surface tradeoff).
5. **Prize cadence/value** for the first draw.
6. **Geo scope:** US-only first? (simplifies sweepstakes law.)

## Notes / decisions log
- 2026-06: roadmap created. Apple Developer account already in hand; everything
  else todo. Web app + Supabase backend are the foundation; iOS is a Capacitor
  wrapper over the same front-end + backend.
