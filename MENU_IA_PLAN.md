# Menu / Navigation IA — Locked Plan

## The principle
Organize by **who it's about**: *me alone* (Play), *me + people* (Community), *my record* (Profile), *my stuff* (Store). Notifications split into **act-now** (banner), **browse** (Activity + dot), **real-time** (toasts).

## Locked map
```
HOME
 ├─ top bar:  🔥 streak   🪙 cash   👤 (Profile)
 ├─ BANNER:   most-urgent act-now item + "+N more" (or "⚔️ Challenge a friend →")
 └─ cards:    Play        Community•        Store

PLAY        Daily · Cash Game · Free Play · Blitz
            + subtle "⚔️ Or challenge a friend →"  → Community ▸ Challenges ▸ New

COMMUNITY   hub, opens on Challenges; header has 👥 People
 ├─ Challenges   inbox (your matches) + New builder      (default)
 ├─ Leaderboard  Cash · Daily (+ group filter)
 ├─ Activity•    the browse feed — carries the unread dot
 └─ 👥 People    Friends (add · requests · list) + Groups (create · list · detail)

PROFILE     (avatar)  Stats · History · Badges · Settings
STORE       shop
```

## Notifications — full model (no double-signaling)
Three surfaces, each one job:
- **Banner = act now.** One slot, shows the single most-urgent *actionable* item (soonest-to-expire challenge first, then friend request), inline action, `+N more →` opens Community ▸ Challenges. Nothing pending → `⚔️ Challenge a friend →` CTA. Challenges always outrank friend requests.
- **Community dot = unread *ambient*.** Lights from unread **Activity**; clears when Activity is viewed. Means "something happened," never "you must act."
- **Toasts = real-time** while in-app (unchanged: `Toaster.svelte` / `notificationStore`, 45s poll).
- **In-match surfaces** for live play: the 💬 chat button + sabotage/chat toasts appear *on the board* during a challenge (already built — keep).
- **Kill** the cut-off number badge on the old Challenge Friends card.

### Each event → where it shows
| Event | Banner (act now) | Activity + dot (browse) | Toast (real-time) | In-match |
|---|:--:|:--:|:--:|:--:|
| Challenge invite / your turn | ✅ | ✅ | ✅ | — |
| Friend request | ✅ (if no challenge waiting) | ✅ | — | — |
| Challenge **result** (won/lost/tie) | ❌ *(nothing to do)* | ✅ | ✅ | — |
| Sabotaged | ❌ | ✅ | ✅ | ✅ banner on board |
| Chat message | ❌ | ✅ | ✅ | ✅ 💬 unread |
| Someone you know played the daily | ❌ | ✅ | — | — |

Key rule: **results never hit the banner** — "you won/lost" is nothing to *do*, so it's a toast in the moment + an Activity entry to browse, not an action prompt. That's what keeps the banner signal clean.

---

## Inventory: exists / moves / net-new
| Piece | Today | Target |
|---|---|---|
| Challenge inbox + builder | modal `showChallenges` (tabbed Inbox/New, +page.svelte) | **moves** → Community ▸ Challenges tab |
| Leaderboard | `/leaderboard` route | reused as Community ▸ Leaderboard tab |
| Activity | `/activity` route | reused as Community ▸ Activity tab + becomes the dot's target |
| Friends / Groups | `/friends`, `/groups` routes | **move** under 👥 People (two tabs) |
| Community submenu | `menuView==='community'` (2 cards: Leaderboard, Activity) | **becomes** the tabbed hub |
| "Challenge Friends" card | top-level home card | **removed** (banner + Community cover it) |
| Banner | `pendingInvite` peek above Play (+page ~1142) | **upgraded** → smart act-now banner |
| Badge on card | red count (clips) | **removed** → Community dot |
| Bell / notifications panel | `showNotifications` panel code remains | **removed** (job moves to Activity) |

---

## Build phases (each shippable on its own)

### Phase 1 — Smart act-now banner + drop the badge  *(home; highest value, user-loved)*
- Upgrade the `pendingInvite` banner into the act-now banner:
  - Source: `getMyMatches()` (already loaded) filtered to my-turn (invited/resume) + `getFriendRequestCount`/list.
  - Order by soonest `respond-by`; show top item + inline action (`Play →` / `Resume →` / `Accept →`).
  - `+N more →` when >1 → opens Community ▸ Challenges.
  - Empty state → `⚔️ Challenge a friend →` CTA.
  - Friend request shows only when no challenge is waiting.
- Remove the clipped count badge on the Challenge Friends card.
- *Ships even before the hub restructure (can still open the existing modal).*

### Phase 2 — Community hub (3 tabs) + fold in Challenges
- Turn `menuView==='community'` into a tabbed hub: **Challenges · Leaderboard · Activity**, default Challenges, with a **👥 People** header button.
- Extract the challenge inbox+builder modal body into `ChallengesPanel.svelte`; render as the Challenges tab. Reuse the leaderboard/activity views in their tabs.
- Home cards → **Play · Community · Store** (remove Challenge Friends card).
- Repoint every `openChallenges()` caller + the `inboxRequest` deep-link → Community ▸ Challenges (result-modal "Challenge Friends" buttons, toast routing, etc.).

### Phase 3 — 👥 People (Friends + Groups)
- `People` screen with **Friends / Groups** tabs (fold in `/friends`, `/groups` content):
  - Friends: 🔍 add by username · REQUESTS (accept/✕) · MY FRIENDS (⚔️ challenge · › profile).
  - Groups: ＋ create · MY GROUPS list · group detail (⚔️ challenge group · 📊 standings · members + invite · leave).
- Wire from the Community 👥 button; roster feeds the New-challenge picker.

### Phase 4 — Activity as the browse inbox + the dot
- Activity = unified feed (results, plays, sabotages, friend requests) with read/unread.
- Community card + Activity tab show an unread **dot** (derive from `unreadCount` / a last-seen marker); mark read on view.
- Toast taps route to the correct Community tab; remove dead `showNotifications` bell panel.

### Phase 5 — Play → "play with friends" subtle link
- In the Play submenu, add a subtle de-emphasized link under the solo modes:
  `⚔️ Or challenge a friend →` → Community ▸ Challenges ▸ New.
- Subtle = small ghost text link, not a card — catches users who open Play looking for multiplayer.

---

## Naming
Keep **"Community"** (spans compete + social; already standardized). Revisit only if it tests soft.

## Open polish (after the structure lands)
- Empty states: no friends / no groups / no challenges yet.
- Swipe-between-items on the banner as an enhancement over `+N more`.
