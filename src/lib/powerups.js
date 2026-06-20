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
