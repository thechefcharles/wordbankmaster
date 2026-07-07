// Achievement badge catalog. Keys match the server's user_badges.badge values.
// Organized by the unified 5-bucket framework: Progression · Skill · Big-moment · Consistency · Social.
/** @type {Record<string, { emoji: string, name: string, desc: string }>} */
export const BADGES = {
	// 🗓️ Daily
	flawless: { emoji: '🎯', name: 'Flawless', desc: 'Solved a Daily with zero wrong letters' },
	streak_7: { emoji: '🔥', name: 'Week Warrior', desc: '7-day Daily play streak' },
	streak_30: { emoji: '👑', name: 'Iron Will', desc: '30-day Daily play streak' },
	week_complete: { emoji: '🗓️', name: 'Perfect Week', desc: 'Played every day of a calendar week' },
	month_complete: {
		emoji: '📅',
		name: 'Perfect Month',
		desc: 'Played every day of a calendar month'
	},

	// 🎰 Cash Game
	cg_bronze: { emoji: '🥉', name: 'Bronze Runner', desc: 'Cashed out a Bronze run' },
	cg_silver: { emoji: '🥈', name: 'Silver Runner', desc: 'Cashed out a Silver run' },
	cg_gold: { emoji: '🥇', name: 'Gold Runner', desc: 'Cashed out a Gold run' },
	cg_run_5: { emoji: '📈', name: 'On a Heater', desc: '5 profitable cash-outs in a row' },
	cg_multiple_10: { emoji: '🚀', name: 'Ten-Bagger', desc: 'Cashed out 10× your buy-in' },
	cg_heat_max: { emoji: '🌋', name: 'Max Heat', desc: 'Rode heat to the tier ceiling' },
	cg_high_roller: { emoji: '💎', name: 'High Roller', desc: 'A $25,000+ cash-out' },
	gold_shark: {
		emoji: '🦈',
		name: 'Gold Shark',
		desc: 'Won a Gold Cash Game run — unlocks the 🦈 Gold Shark title'
	},

	// ⚡ Blitz
	bz_bronze: { emoji: '🥉', name: 'Bronze Blitzer', desc: 'Played a Bronze Blitz run' },
	bz_silver: { emoji: '🥈', name: 'Silver Blitzer', desc: 'Played a Silver Blitz run' },
	bz_gold: { emoji: '🥇', name: 'Gold Blitzer', desc: 'Played a Gold Blitz run' },
	bz_speed_demon: { emoji: '😈', name: 'Speed Demon', desc: 'Solved 10 in a single Blitz run' },
	bz_combo_3: { emoji: '🔗', name: 'Combo x3', desc: 'Hit a ×3 combo in Blitz' },
	bz_combo_5: { emoji: '⚡', name: 'Combo x5', desc: 'Maxed a ×5 combo in Blitz' },
	bz_high_roller: { emoji: '💰', name: 'Big Blitz', desc: 'A $5,000+ Blitz payout' },

	// ⚔️ Challenges
	first_blood: { emoji: '🩸', name: 'First Blood', desc: 'Won your first challenge' },
	gold_duelist: { emoji: '⚔️', name: 'Gold Duelist', desc: 'Won a Gold challenge' },
	hustler: { emoji: '🤝', name: 'Hustler', desc: 'Won 10 challenges' },

	// 💸 Economy
	paid_in_full: { emoji: '🧾', name: 'Paid in Full', desc: 'Cleared a loan from the Shark' }
};

/** @param {string} id */
export function badgeInfo(id) {
	return BADGES[id] || { emoji: '🏅', name: id, desc: '' };
}
