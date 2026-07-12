// Feature flags — flip to re-enable a hidden feature (code + DB stay intact).

// ⚡ Blitz (timed, money-staked mode) is RETIRED — kept behind this flag rather than
// ripped out. `false` hides the Play-menu Blitz tile AND the Standard/Blitz toggle in
// the challenge builder (all challenges are Standard). Its power-ups are deactivated in
// the `powerups` catalog. Leaving this off is the intended state; the remaining Blitz
// code is dead weight slated for a dedicated excision. Only flip to `true` if the
// product decision to drop Blitz is reversed.
export const BLITZ_ENABLED = false;
