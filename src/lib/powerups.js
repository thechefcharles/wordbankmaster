// Power-up catalog. Keys match server user_powerups.powerup values.
/** @type {Record<string, { emoji: string, name: string, desc: string }>} */
export const POWERUPS = {
  free_reveal: { emoji: '🎟️', name: 'Free Reveal', desc: 'One free smart reveal (no $ charge)' },
  // Phase 3b: extra_bank, discount, insurance, vowel_vision, double_payout…
};

/** @param {string} id */
export function powerupInfo(id) {
  return POWERUPS[id] || { emoji: '⚡', name: id, desc: '' };
}
