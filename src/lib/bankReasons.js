// Single source of truth for statement / ledger line-item names. Used by the /bank
// Statement and the in-game bank modal so they never drift apart.
//
// Naming convention (Title Case throughout):
//   • buy-ins / stakes  → "<Mode> Entry"
//   • winnings          → "<Mode> Payout"  (or Bounty for per-solve credit)
//   • given, not won    → "<X> Reward"
//   • store spend       → "<X> Purchase"
//   • loans             → "Loan <X>"

/** @type {Record<string, string>} */
const LABELS = {
	// 🗓️ Daily
	daily_win: 'Daily Reward',
	daily_reward: 'Daily Reward',
	attendance: 'Attendance Reward',
	makeup_reward: 'Make-Up Reward',
	quest_reward: 'Quest Reward',

	// 🎰 Cash Game
	cashgame_buyin: 'Cash Game Entry',
	cashgame_cashout: 'Cash Game Payout',
	climb_bounty: 'Cash Game Bounty',
	climb_letter: 'Cash Game Letter',

	// ⚡ Blitz
	blitz_buyin: 'Blitz Entry',
	blitz_payout: 'Blitz Payout',

	// ⚔️ Challenges (wager_* are the challenge staking system)
	challenge_payout: 'Challenge Payout',
	wager_stake: 'Challenge Entry',
	wager_win: 'Challenge Payout',
	wager_refund: 'Challenge Refund',

	// 🛍️ Store
	cosmetic_buy: 'Store Purchase',
	powerup_buy: 'Power-Up Purchase',

	// 🦈 Loans
	loan_take: 'Loan Received',
	loan_repay: 'Loan Repayment',
	loan_skim: 'Loan Auto-Payment',

	// 💱 Credits / legacy
	buy_credits: 'Credits Purchase',
	arcade_cashout: 'Arcade Payout',
	freeplay_reward: 'Free Play Reward',
	freeplay_cashout: 'Credits Exchange'
};

/** Friendly, uniform label for a bank_ledger reason. Unknown reasons Title-Case the raw key.
 * @param {string} reason @returns {string} */
export function reasonLabel(reason) {
	return (
		LABELS[reason] ||
		String(reason || '')
			.replace(/_/g, ' ')
			.replace(/\b\w/g, (c) => c.toUpperCase())
	);
}
