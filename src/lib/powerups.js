// Power-up catalog. Keys match server user_powerups.powerup values.
// pregame: chosen before a daily starts (selection modal). Otherwise used in-game.
/** @type {Record<string, { emoji: string, name: string, desc: string, pregame?: boolean }>} */
export const POWERUPS = {
  free_reveal:  { emoji: '🎟️', name: 'Free Reveal',  desc: 'One free smart reveal (no $ charge)' },
  extra_bank:   { emoji: '💰', name: '+$250 Start',  desc: 'Begin the puzzle with $1,250', pregame: true },
  discount:     { emoji: '🏷️', name: 'Discount',     desc: 'All letters −25% this puzzle', pregame: true },
  insurance:    { emoji: '🛡️', name: 'Insurance',    desc: 'Your first wrong guess is free', pregame: true },
  vowel_vision: { emoji: '👁️', name: 'Vowel Vision', desc: 'Vowels cost half this puzzle', pregame: true },
  // Phase 4: double_payout (arcade)
};

/** @param {string} id */
export function powerupInfo(id) {
  return POWERUPS[id] || { emoji: '⚡', name: id, desc: '' };
}

// Daily Modifier — the single shared effect active for everyone on a given day.
// Keys match the server _daily_modifier() pool. `blurb` is the short "twist" line.
/** @type {Record<string, { emoji: string, name: string, blurb: string }>} */
export const MODIFIERS = {
  discount:     { emoji: '🏷️', name: 'Discount Day', blurb: 'Every letter is 25% off' },
  vowel_vision: { emoji: '👁️', name: 'Vowel Vision', blurb: 'Vowels cost half price' },
  extra_bank:   { emoji: '💰', name: 'Big Bank',      blurb: 'Start with an extra $250' },
  insurance:    { emoji: '🛡️', name: 'Insured',       blurb: 'Your first wrong guess is free' }
};

/** @param {string} id */
export function modifierInfo(id) {
  return MODIFIERS[id] || null;
}
