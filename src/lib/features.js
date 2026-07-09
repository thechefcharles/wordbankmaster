// Feature flags — flip to re-enable a hidden feature (code + DB stay intact).

// ⚡ Blitz (timed, money-staked mode) is HIDDEN for the first App Store submission.
// Timed money modes are the hardest to anti-cheat, so per the launch plan Blitz is a
// planned fast-follow. `false` hides the Play-menu Blitz tile AND the Standard/Blitz
// toggle in the challenge builder (all challenges default to Standard). In-flight Blitz
// matches still resolve. Set to `true` to restore it.
export const BLITZ_ENABLED = false;
