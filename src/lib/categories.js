// The 12 puzzle categories. `value` is the exact string stored on
// daily_puzzles.category (emoji included); used by the Challenge builder's picker.
// `icon` keys into CategoryIcon.svelte for the line-icon (non-emoji) rendering.
/** @type {{ value: string, label: string, emoji: string, icon: string }[]} */
export const CATEGORIES = [
	{ value: 'Movies & TV 🎬', label: 'Movies & TV', emoji: '🎬', icon: 'movies' },
	{ value: 'Music 🎵', label: 'Music', emoji: '🎵', icon: 'music' },
	{ value: 'Famous People 🌟', label: 'Famous People', emoji: '🌟', icon: 'famous' },
	{ value: 'Food & Drink 🍔', label: 'Food & Drink', emoji: '🍔', icon: 'food' },
	{ value: 'Places & Travel ✈️', label: 'Places & Travel', emoji: '✈️', icon: 'travel' },
	{ value: 'Sports 🏆', label: 'Sports', emoji: '🏆', icon: 'sports' },
	{ value: 'Phrases & Sayings 🗣️', label: 'Phrases & Sayings', emoji: '🗣️', icon: 'phrases' },
	{ value: 'Science & Nature 🔬', label: 'Science & Nature', emoji: '🔬', icon: 'science' },
	{ value: 'Books & Characters 📚', label: 'Books & Characters', emoji: '📚', icon: 'books' },
	{ value: 'Video Games 🎮', label: 'Video Games', emoji: '🎮', icon: 'games' },
	{ value: 'Brands & Logos 🏷️', label: 'Brands & Logos', emoji: '🏷️', icon: 'brands' },
	{ value: 'Tech & Internet 💻', label: 'Tech & Internet', emoji: '💻', icon: 'tech' }
];

/** Category value/label (emoji may be baked in) → its entry, or null. */
export function categoryMeta(/** @type {string} */ value) {
	const raw = String(value ?? '');
	return (
		CATEGORIES.find((c) => c.value === raw || c.label === raw) ||
		CATEGORIES.find((c) => c.label === raw.replace(/[^\x20-\x7E]+/g, '').trim()) ||
		null
	);
}

/** Clean display label with no emoji (falls back to stripping non-ASCII). */
export function categoryLabel(/** @type {string} */ value) {
	const m = categoryMeta(value);
	return m
		? m.label
		: String(value ?? '')
				.replace(/[^\x20-\x7E]+/g, '')
				.trim();
}
