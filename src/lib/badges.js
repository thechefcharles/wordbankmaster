// Achievement badge catalog. Keys match the server's user_badges.badge values.
/** @type {Record<string, { emoji: string, name: string, desc: string }>} */
export const BADGES = {
  flawless:  { emoji: '🎯', name: 'Flawless',     desc: 'Solved a daily with zero wrong letters' },
  gold_bank: { emoji: '💎', name: 'Gold Bank',    desc: 'Finished a daily with $700+' },
  streak_7:  { emoji: '🔥', name: 'Week Warrior',  desc: '7-day daily streak' },
  streak_30: { emoji: '👑', name: 'Iron Will',     desc: '30-day daily streak' },
};

/** @param {string} id */
export function badgeInfo(id) {
  return BADGES[id] || { emoji: '🏅', name: id, desc: '' };
}
