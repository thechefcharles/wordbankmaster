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
