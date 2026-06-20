// Power-up catalog. Keys match the server ids.
// `armed`: an effect that arms on the CURRENT puzzle (shown as active). Otherwise
// it fires instantly when used. Used by the arcade tray + active-effect badges.
/** @type {Record<string, { emoji: string, name: string, desc: string, armed?: boolean }>} */
export const POWERUPS = {
  free_reveal:     { emoji: '🎟️', name: 'Free Reveal',     desc: 'One free smart reveal (no $ charge)' },
  extra_bank:      { emoji: '💰', name: '+$250',           desc: 'Add $250 to your bankroll now' },
  discount:        { emoji: '🏷️', name: 'Discount',        desc: 'All letters −25% this puzzle', armed: true },
  insurance:       { emoji: '🛡️', name: 'Insurance',       desc: 'Your first wrong guess is free', armed: true },
  vowel_vision:    { emoji: '👁️', name: 'Vowel Vision',    desc: 'Vowels cost half this puzzle', armed: true },
  double_payout:   { emoji: '💎', name: 'Double Payout',   desc: 'Bank 2× on this puzzle', armed: true },
  multiplier_boost:{ emoji: '⚡', name: 'Multiplier Boost', desc: '+0.5× to your multiplier now' },
  shield:          { emoji: '🔰', name: 'Shield',          desc: 'A bust here keeps your multiplier', armed: true },
  skip:            { emoji: '⏭️', name: 'Skip',            desc: 'Skip this puzzle, keep your multiplier' },
  extra_try:       { emoji: '❤️', name: 'Extra Try',       desc: '+1 solve attempt' }
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
