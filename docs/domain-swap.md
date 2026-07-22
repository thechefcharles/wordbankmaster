# Swapping to a custom domain (e.g. playwordbank.com) — for later

Not needed for launch. `wordbanksvelte.vercel.app` works fine as the Support/Privacy/backend URL.
This is future polish. Do it in two phases so you never need an urgent App Store rebuild.

## ⚠️ The one thing to never break
The **shipped iOS binary loads `server.url = https://wordbanksvelte.vercel.app`** (baked into the
build, `capacitor.config.json`). Existing installs will keep loading that URL, so **keep
`wordbanksvelte.vercel.app` alive and serving the app** even after you add a custom domain. Moving
the *native app* itself to the new domain requires a new build + App Store review (Phase 2, optional).

---

## Phase 1 — website / support / share URLs (NO app rebuild, no Apple review)
Everything user-facing except the native shell can move to the custom domain with zero rebuild.

1. **Buy the domain** (Namecheap / Cloudflare / etc.). `wordbank.com` is taken (the translation co) —
   use `playwordbank.com` / `getwordbank.com` / `wordbankapp.com`. See [[wordbank-trademark]].
2. **Add it to the Vercel project** → Vercel dashboard → the `wordbanksvelte` project → Settings →
   Domains → Add `playwordbank.com` (+ `www`). Add the DNS records Vercel gives you at your registrar.
   SSL is automatic. Both domains now serve the same app — `wordbanksvelte.vercel.app` keeps working.
3. **Set `VITE_SITE_URL`** in Vercel env → `https://playwordbank.com` → redeploy. Share text
   (`buildShareText()` in `+page.svelte`) then links to the new domain instead of the vercel.app fallback.
4. **Supabase Auth** (dashboard → Authentication → URL Configuration):
   - Set **Site URL** → `https://playwordbank.com` (used in reset/confirm email links `{{ .SiteURL }}`).
   - Add `https://playwordbank.com/**` to the **Redirect URLs** allow-list (OAuth / password reset use
     `window.location.origin`, so the web app on the new domain needs to be allow-listed).
   - Keep the vercel.app entries too, so the existing native shell keeps working.
5. **App Store Connect metadata** (editable without a new build): update **Support URL** and
   **Marketing URL** on the version page, and the **Privacy Policy URL** in App Privacy →
   `https://playwordbank.com/support` and `/privacy`.
6. **Verify:** the new domain loads the app; `/privacy` `/terms` `/support` work on it (they're relative
   routes, so they just work); test password-reset + Google/Apple sign-in **on web** after the Supabase
   allow-list change; confirm a share link uses the new domain.

## Phase 2 — move the native app onto the custom domain (OPTIONAL, needs a rebuild)
Only cosmetic — the webview URL isn't visible to users. Low priority.

1. Edit `capacitor.config.json` → `server.url` → `https://playwordbank.com`.
2. `npx cap sync ios` → bump the **Build** number → Xcode **Archive → Distribute → Upload**.
3. Submit the new build for review, select it on a new version.
4. Only after all users are on the new build can you retire `wordbanksvelte.vercel.app` (in practice,
   just leave it alive — it's free and harmless).

## Files/config that reference the domain (checklist)
- `capacitor.config.json` → `server.url` (native — Phase 2)
- Vercel env `VITE_SITE_URL` (share links — Phase 1)
- Supabase Auth Site URL + Redirect allow-list (Phase 1)
- App Store Connect: Support URL, Marketing URL, Privacy Policy URL (Phase 1)
- `/privacy` `/terms` `/support` pages = relative routes, no change needed
- Contact email is a gmail, not domain-based — no change
