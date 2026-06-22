// Achievement badge catalog. Keys match the server's user_badges.badge values.
/** @type {Record<string, { emoji: string, name: string, desc: string }>} */
export const BADGES = {
  flawless:  { emoji: '🎯', name: 'Flawless',     desc: 'Solved a daily with zero wrong letters' },
  gold_bank: { emoji: '💎', name: 'Gold Bank',    desc: 'Finished a daily with $700+' },
  streak_7:  { emoji: '🔥', name: 'Week Warrior',  desc: '7-day daily streak' },
  streak_30: { emoji: '👑', name: 'Iron Will',     desc: '30-day daily streak' },
  week_complete:  { emoji: '🗓️', name: 'Perfect Week',  desc: 'Played every day of a calendar week' },
  month_complete: { emoji: '📅', name: 'Perfect Month', desc: 'Played every day of a calendar month' },
  climb_50:  { emoji: '🧗', name: 'Climber',     desc: 'Reached puzzle #50 in the Cash Game' },
  climb_100: { emoji: '🏔️', name: 'Mountaineer', desc: 'Reached puzzle #100 in the Cash Game' },
  climb_500: { emoji: '🚀', name: 'Summit',      desc: 'Reached puzzle #500 in the Cash Game' },
  debt_free: { emoji: '💸', name: 'Debt-Free',   desc: 'Paid off a loan in full' },
  hustler:   { emoji: '🤝', name: 'Hustler',     desc: 'Won 10 challenges' },
};

/** @param {string} id */
export function badgeInfo(id) {
  return BADGES[id] || { emoji: '🏅', name: id, desc: '' };
}
