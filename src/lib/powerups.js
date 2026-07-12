// Daily Modifier — the single shared effect active for everyone on a given day.
// Keys match the server _daily_modifier() pool. `blurb` is the short "twist" line.
// `emoji` holds an Icon.svelte name (rendered via <Icon>).
/** @type {Record<string, { emoji: string, name: string, blurb: string }>} */
export const MODIFIERS = {
	discount: { emoji: 'tag', name: 'Discount Day', blurb: 'Every letter is 25% off' },
	vowel_vision: { emoji: 'eye', name: 'Vowel Vision', blurb: 'Vowels cost half price' },
	flat_rate: { emoji: 'coin', name: 'Flat Rate', blurb: 'Every letter is a flat $50' },
	free_vowel: { emoji: 'letter-a', name: 'Free Vowel', blurb: 'One vowel revealed free' },
	consonant_sale: { emoji: 'percent', name: 'Consonant Sale', blurb: 'Consonants are 25% off' },
	head_start: { emoji: 'bolt', name: 'Head Start', blurb: 'First letter of each word free' },
	insured: { emoji: 'shield', name: 'Insured', blurb: 'Your first wrong letter is free' }
};

/** @param {string} id */
export function modifierInfo(id) {
	return MODIFIERS[id] || null;
}
