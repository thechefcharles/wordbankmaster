# Emoji → Line-Icon Sweep

Goal: remove all emojis from the **user-facing** app and replace with the line-icon design
system. Inventory taken 2026-07-12: **139 distinct emojis, ~785 occurrences**.

**Caveat:** the raw count includes emojis in **code comments** (not rendered) — the real
UI surface is smaller. Existing coverage: `ModeIcon` (daily/climb/match/blitz),
`CategoryIcon` (12 puzzle categories). Power-ups use a `PUP_ICON` map that is currently
**emoji strings** (needs swapping to icons, not just find/replace).

## Foundation ✅ (Icon.svelte shipped, PR #576 — starter control/sound set)

### original plan:

## Foundation (do first)

Build a single reusable **`Icon.svelte`** with a named line-icon set (inline SVG, `stroke`

- `currentColor`, sized like ModeIcon), so every replacement is `<Icon name="…" />`. Every
  wave below adds the names it needs. ~15–20 new icons need drawing.

---

## Wave 1 — Nav bar + controls + sound (highest visibility; you called these out)

**Progress:** ✅ sound/haptics/music controls done (PR #576). Remaining: other nav/control glyphs.

Standard glyphs, all have clean line-icon equivalents:

- **Controls:** ☰ menu · ❌/⛔/✕ close/cancel · ▶ ◀ play/prev · ↗ ↪ ↩ arrows · ✅/✓ check · ⚙ settings · 🗑 trash · ✏/✍ edit · 🔍 search · ❓/ℹ help/info · 🏠 home · 🎒 vault/bag · 👤/🧑 profile · 🔗 link · 📤/📥 share/import · 🔄/🔁 refresh
- **Sound/volume (the "sound one"):** 🔊 🔈 🔇 🔆 volume states · 📳 📴 vibrate · 🎵/🎶 music
- **Lock/security:** 🔒 🔐 🔓 🔑 lock/pin

## Wave 2 — Money & economy (semantic, heavy use)

Needs **new** line icons (design system has none yet):

- 💰 💵 cash · 💳 card · 🏦 bank · 🏧 overdrive/ATM · 🪙 coin · 💸 out-of-budget ·
  🧾 receipt · 💎 jackpot/gem · 📈 💹 growth · 💱 exchange

## Wave 3 — Modes, ranks, awards

- Modes: 📅/🗓 daily · ⚔ challenge · 🎰 cash game · 🧗 climb → mostly **ModeIcon already**;
  audit call sites still using the emoji.
- Ranks/awards (**new icons**): 🏆 winner · 🥇 🥈 🥉 tiers/medals · 🏅 badge · 👑 owner ·
  🎯 objective/target · 🔥 heat/streak

## Wave 4 — Power-ups, buffs & sabotage (swap PUP_ICON map to icons)

**Progress:** ✅ Store (PUP_META) + Inventory (META) power-up icons done (PR #577). Icon.svelte now has the full ~65-icon palette. Remaining: in-game vault/hotbar (mixed twist/boost/pup/sabotage sources) + DEBUFF banner + sabotage picker.

- Buffs: 🛡 heat-shield · 🏧 overdrive · ⏭ free-skip · 🔍 free-reveal · 🅰 free-vowel ·
  🏷 half-off · 👁 vowel-vision · 📖 reveal-word · 💡 hint · 🔚 last-letters · 💥 boost
- Sabotage/debuffs: 😈 sabotage · 🌫 fog · 🚧 toll · 🚫 vowel-block · 🔒 lock · 💸 tax

## Wave 5 — Social, alerts, misc

- Social: 👥 groups · 💬 chat · 🤝 friendly/tie · 🙋 request · 👋 hi
- Alerts: 🚨 danger · ⚠ warning · 💀/😬 bust · 🔔 bell

## Wave 6 — Decorative flourishes (DECISION: convert or drop?)

Mostly celebration/onboarding sparkle with no functional meaning:

- ✨ 🎉 🎊 🌟 🎁 🧠 🚀 🌋 🩸 🎨 🌍 🖼 🧩 🔮 📣 🎲 🌀 …
- **Recommendation:** drop most (or replace celebration with a single tasteful confetti/
  spark icon) rather than draw one-off icons for each.

## Category-puzzle emojis

🍔 🎬 ✈ 🔬 📚 💻 … are puzzle categories — **CategoryIcon already exists**; just route call
sites through it.

---

## Decisions needed

1. **New icons OK?** Waves 2–4 need ~15–20 custom line-icons drawn. Confirm that's the plan
   (vs. keeping a few semantic emojis like 🏆/🔥).
2. **Decorative (Wave 6):** drop them, or convert to icons? (Recommend drop/minimize.)
3. **Order:** proposed Wave 1 → 6. Ship each wave as its own PR.

## Suggested sequencing

Foundation `Icon.svelte` + **Wave 1 (nav/controls/sound)** first — highest visibility,
lowest risk. Then money → modes/ranks → power-ups → social/alerts → decorative.
