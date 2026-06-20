// Power-up catalog. Keys match the server ids. Arcade earns exactly 3, each by a
// special feat (most solves earn nothing). `armed`: arms on the CURRENT puzzle
// (shown as ON). Otherwise it fires instantly when used. `feat`: the move that
// earns it (shown in the solve modal so players learn the feats).
/** @type {Record<string, { emoji: string, name: string, desc: string, feat: string, armed?: boolean }>} */
export const POWERUPS = {
  multiplier_boost:{ emoji: '⚡', name: 'Multiplier Boost', desc: '+0.5× to your streak now',     feat: 'Blind Solve' },
  double_payout:   { emoji: '💎', name: 'Double Payout',   desc: 'Next solve pays 2×', armed: true, feat: 'Consonant King' },
  extra_guess:     { emoji: '❤️', name: 'Extra Guess',     desc: '+1 to your guess pool',         feat: 'Hot Streak' }
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
