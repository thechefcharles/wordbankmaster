// Credit-tier → WordBank card name + a plain-English "how it affects loans" line.
// The card ladder (worst → best): Secured · Freedom · Plus · Preferred · Reserve.
// Keep in sync with the server's _credit_effective_cap / _credit_rate_adjust.

/** @type {Record<string, string>} */
const CARD_NAME = {
	Excellent: 'Reserve',
	Good: 'Preferred',
	Fair: 'Plus',
	Poor: 'Freedom',
	Bad: 'Secured'
};

/** @param {string} tier @returns {string} */
export function cardName(tier) {
	return CARD_NAME[tier] || 'Preferred';
}

// The full ladder (best → worst) for the "which card needs what score" modal.
// Score bands mirror the server's _credit_tier(); effects mirror _credit_effective_cap /
// _credit_rate_adjust. Credit runs 300–850.
/** @type {{ tier:string, card:string, range:string, min:number, effect:string }[]} */
export const TIER_LADDER = [
	{
		tier: 'Excellent',
		card: 'Reserve',
		range: '780–850',
		min: 780,
		effect: '1.25× loan limit · −3%/day interest'
	},
	{
		tier: 'Good',
		card: 'Preferred',
		range: '650–779',
		min: 650,
		effect: 'Standard loan limit & interest'
	},
	{
		tier: 'Fair',
		card: 'Plus',
		range: '560–649',
		min: 560,
		effect: '0.5× loan limit · +3%/day interest'
	},
	{
		tier: 'Poor',
		card: 'Freedom',
		range: '400–559',
		min: 400,
		effect: '$250 loan limit · +6%/day interest'
	},
	{ tier: 'Bad', card: 'Secured', range: 'Below 400', min: 300, effect: 'Borrowing locked' }
];

/** How this tier changes your loan cap + interest rate. @param {string} tier @returns {string} */
export function tierEffect(tier) {
	switch (tier) {
		case 'Excellent':
			return '1.25× loan limit · −3%/day interest';
		case 'Good':
			return 'Standard loan limit & interest';
		case 'Fair':
			return '0.5× loan limit · +3%/day interest';
		case 'Poor':
			return '$250 loan limit · +6%/day interest';
		case 'Bad':
			return 'Borrowing locked';
		default:
			return 'Standard loan limit & interest';
	}
}
