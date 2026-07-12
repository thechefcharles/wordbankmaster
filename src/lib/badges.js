// Achievement badge catalog. Keys match the server's user_badges.badge values.
// Organized by the unified 5-bucket framework: Progression · Skill · Big-moment · Consistency · Social.
// `icon` = Icon.svelte name (rendered via <Icon>).
/** @type {Record<string, { icon: string, name: string, desc: string }>} */
export const BADGES = {
	// Daily
	flawless: { icon: 'target', name: 'Flawless', desc: 'Solved a Daily with zero wrong letters' },
	streak_7: { icon: 'fire', name: 'Week Warrior', desc: '7-day Daily play streak' },
	streak_30: { icon: 'crown', name: 'Iron Will', desc: '30-day Daily play streak' },
	week_complete: {
		icon: 'calendar',
		name: 'Perfect Week',
		desc: 'Played every day of a calendar week'
	},
	month_complete: {
		icon: 'calendar',
		name: 'Perfect Month',
		desc: 'Played every day of a calendar month'
	},

	// Cash Game
	cg_bronze: { icon: 'medal', name: 'Bronze Runner', desc: 'Cashed out a Bronze run' },
	cg_silver: { icon: 'medal', name: 'Silver Runner', desc: 'Cashed out a Silver run' },
	cg_gold: { icon: 'medal', name: 'Gold Runner', desc: 'Cashed out a Gold run' },
	cg_run_5: { icon: 'growth', name: 'On a Heater', desc: '5 profitable cash-outs in a row' },
	cg_multiple_10: { icon: 'rocket', name: 'Ten-Bagger', desc: 'Cashed out 10× your buy-in' },
	cg_heat_max: { icon: 'fire', name: 'Max Heat', desc: 'Rode heat to the tier ceiling' },
	cg_high_roller: { icon: 'gem', name: 'High Roller', desc: 'A $25,000+ cash-out' },
	gold_shark: {
		icon: 'shark',
		name: 'Gold Shark',
		desc: 'Won a Gold Cash Game run — unlocks the Gold Shark title'
	},

	// Challenges
	first_blood: { icon: 'drop', name: 'First Blood', desc: 'Won your first challenge' },
	gold_duelist: { icon: 'swords', name: 'Gold Duelist', desc: 'Won a Gold challenge' },
	hustler: { icon: 'handshake', name: 'Hustler', desc: 'Won 10 challenges' },

	// Economy
	paid_in_full: { icon: 'receipt', name: 'Paid in Full', desc: 'Cleared a loan from the Shark' },
	credit_700: { icon: 'card', name: '700 Club', desc: 'Reached a 700 credit score' },
	credit_800: { icon: 'bank', name: '800 Club', desc: 'Reached an 800 credit score' },
	credit_850: { icon: 'gem', name: 'Perfect 850', desc: 'Hit a perfect 850 credit score' }
};

/** @param {string} id */
export function badgeInfo(id) {
	return BADGES[id] || { icon: 'badge', name: id, desc: '' };
}
