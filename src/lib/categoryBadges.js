// Per-category level-up badges (from category_stats.solves) + global milestones.

/** Ascending tiers — a category badge levels up as you solve more in it. */
// icon = Icon.svelte name (rendered via <Icon>).
export const CATEGORY_TIERS = [
	{ key: 'bronze', name: 'Bronze', icon: 'medal', at: 3 },
	{ key: 'silver', name: 'Silver', icon: 'medal', at: 10 },
	{ key: 'gold', name: 'Gold', icon: 'medal', at: 25 },
	{ key: 'diamond', name: 'Diamond', icon: 'gem', at: 60 }
];

/**
 * Current tier + progress toward the next, for a given solve count.
 * @param {number} solves
 */
export function categoryProgress(solves) {
	let current = null;
	for (const t of CATEGORY_TIERS) if (solves >= t.at) current = t;
	const next = CATEGORY_TIERS.find((t) => solves < t.at) || null;
	const prevAt = current ? current.at : 0;
	const progress = next ? (solves - prevAt) / (next.at - prevAt) : 1;
	return {
		solves,
		current, // {medal,name,at} or null (no tier yet)
		next, // {medal,name,at} or null (maxed)
		toNext: next ? next.at - solves : 0,
		progress: Math.max(0, Math.min(1, progress))
	};
}

/** Global "total puzzles solved" milestone achievements (any mode). */
export const SOLVE_MILESTONES = [
	{ id: 'm10', icon: 'sprout', name: 'Getting Started', at: 10, desc: 'Solve 10 puzzles' },
	{ id: 'm50', icon: 'edit', name: 'Wordsmith', at: 50, desc: 'Solve 50 puzzles' },
	{ id: 'm150', icon: 'bolt', name: 'Phrase Fiend', at: 150, desc: 'Solve 150 puzzles' },
	{ id: 'm500', icon: 'star', name: 'Word Wizard', at: 500, desc: 'Solve 500 puzzles' }
];

/** A standalone achievement for earning Gold in every category. */
export const COLLECTOR = {
	id: 'collector',
	icon: 'badge',
	name: 'Collector',
	desc: 'Reach Gold in all 12 categories'
};
