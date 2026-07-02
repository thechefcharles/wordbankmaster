# WordBank

WordBank is a Wheel-of-Fortune-style phrase-guessing game built as a SvelteKit web
app and shipped to iOS as a native app via Capacitor. Players buy letters, solve
phrases, and manage a bankroll across several game modes:

- **Daily** — one server-authoritative puzzle per day, with twists, boosts, and a
  global leaderboard.
- **Climb (Cash Game)** — an arcade "gauntlet" mode: keep solving puzzles up the
  ladder, double-or-nothing your winnings, or cash out before you bust.
- **Free Play** — untimed practice across 12 categories (Movies & TV, Music, Sports,
  Tech & Internet, etc.) that trickles credits back into your bank.
- **Challenges / Matches** — head-to-head PvP: build a challenge, invite a friend or
  group, and race them on the same puzzle with powerups and sabotage.

Around the core game loop sits a social/meta layer: profiles and avatars, a bank
(net worth, bankroll, credits), win streaks and streak freezes, badges, friends,
groups with realtime chat, notifications, and a shop for powerups and cosmetics.

**Platforms**

- **Web** — SvelteKit app deployed to Vercel (`@sveltejs/adapter-vercel`).
- **iOS** — the same web build wrapped in a native shell with
  [Capacitor](https://capacitorjs.com), built and signed through Xcode.

## Tech stack

- [SvelteKit](https://svelte.dev/docs/kit) + [Vite](https://vitejs.dev)
- [Supabase](https://supabase.com) (Postgres, Auth, Realtime) as the backend
- [Capacitor](https://capacitorjs.com) for the iOS wrapper

## Local development

1. **Clone the repo**

   ```bash
   git clone <repo-url>
   cd wordbank
   ```

2. **Install dependencies**

   ```bash
   npm ci
   ```

3. **Configure environment variables**

   Copy the example env file and fill in your Supabase project's credentials:

   ```bash
   cp .env.example .env
   ```

   ```
   VITE_SUPABASE_URL=https://your-project-id.supabase.co
   VITE_SUPABASE_ANON_KEY=your-anon-key-here
   ```

   Both values are available in the Supabase dashboard under
   **Project Settings → API** (see [Supabase project](#supabase-project) below).

4. **Run the dev server**

   ```bash
   npm run dev

   # or start the server and open the app in a new browser tab
   npm run dev -- --open
   ```

Other useful scripts:

```bash
npm run build   # production build
npm run preview # preview the production build locally
npm run check   # svelte-kit sync + svelte-check (type checking)
npm run lint    # prettier --check + eslint
npm run format  # prettier --write
```

## Supabase project

The backend (Postgres schema, RLS policies, RPC functions, and Auth) lives in a
Supabase project. Ask a maintainer for access to the dashboard at
[app.supabase.com](https://app.supabase.com) if you need to view logs, run SQL, or
manage secrets.

There is no `supabase/migrations` folder managed by the Supabase CLI — schema
changes are plain, incrementally-named SQL files at the repo root
(`supabase-*.sql`), one per feature or fix. To bring a database up to date:

1. Open the target project's **SQL Editor** in the Supabase dashboard (or connect
   with `psql`/the Supabase CLI using the project's connection string).
2. On a **fresh** database, run the base schema first, in this order:
   1. `supabase-schema-base.sql`
   2. `supabase-create-profile-trigger.sql`
   3. `supabase-daily-leaderboard.sql`
   4. `supabase-daily-server-authoritative.sql`
   5. `supabase-security-hardening.sql` (revokes — must be last)
3. Apply the remaining `supabase-*.sql` files in the order they were added to the
   repo (check `git log --diff-filter=A --name-only -- 'supabase-*.sql'` for the
   chronological order, or ask a maintainer if history isn't available). Each file
   is a self-contained migration for one feature (challenges, climb, badges,
   freeplay, etc.) and is written to be safe to re-run (`IF NOT EXISTS` /
   `ADD COLUMN IF NOT EXISTS` where applicable).
4. Seed files such as `supabase-puzzles-seed.sql`,
   `supabase-puzzles-seed-expansion.sql`, `supabase-puzzles-seed-expansion-2.sql`,
   `supabase-daily-puzzles-seed.sql`, and `supabase-arcade-seed.sql` populate puzzle
   content and should be run after their corresponding schema files.

## iOS build (Capacitor)

The iOS app wraps the deployed web build using Capacitor and lives in `ios/App`
(an Xcode project using Swift Package Manager for Capacitor's dependencies — no
CocoaPods). `capacitor.config.json` points the native shell at the deployed web
app URL.

1. Build (or point `capacitor.config.json`'s `server.url` at) the web app you want
   to ship.
2. Sync the native project with the latest Capacitor config/plugins:

   ```bash
   npm run cap:sync   # cap sync ios
   ```

3. Open the project in Xcode to build, run on a simulator/device, or archive for
   release:

   ```bash
   npm run cap:open   # cap open ios
   ```

Building and running from Xcode requires Xcode with an iOS SDK installed, plus a
valid signing certificate/provisioning profile for on-device runs or App Store
submission.
