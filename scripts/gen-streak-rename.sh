#!/usr/bin/env bash
set -euo pipefail
# Generates the daily-streak column rename migration. Renames the 4 columns and rewrites
# every referencing function, preserving all OUTPUT names (json keys, AS aliases, RETURNS
# TABLE columns) so the frontend contract is untouched — only column references change.

DB="$1"
FUNCS=(_daily_bounty_mult _finalize_daily daily_start get_daily_board get_daily_leaderboard \
  get_daily_status get_friends_daily_leaderboard get_player_anomaly_summary get_profile_detail \
  get_profile_stats get_public_profile get_streak_overview record_daily_result \
  get_all_users_leaderboard get_leaderboard_by_period)
# functions that expose a streak as a RETURNS TABLE output column → must DROP before recreate
DROP_FIRST=(get_all_users_leaderboard get_leaderboard_by_period)

mkdir -p /tmp/fnx
rm -f /tmp/fnx/*.sql

read -r -d '' PIPE <<'PERL' || true
s/'play_streak',\s*play_streak\b/\@KV1\@/g;
s/'play_streak'/\@K_ps\@/g;
s/AS\s+play_streak\b/\@A_ps\@/g;
s/AS\s+highest_play_streak\b/\@A_hps\@/g;
s/AS\s+current_solve_streak\b/\@A_css\@/g;
s/AS\s+best_solve_streak\b/\@A_bss\@/g;
s/\bhighest_play_streak(\s+integer)/\@R_hps\@$1/g;
s/\bplay_streak(\s+integer)/\@R_ps\@$1/g;
s/\bhighest_play_streak\b/\@BDPS\@/g;
s/\bbest_solve_streak\b/best_daily_solve_streak/g;
s/\bcurrent_solve_streak\b/current_daily_solve_streak/g;
s/\bplay_streak\b/current_daily_play_streak/g;
s/\@BDPS\@/best_daily_play_streak/g;
s/\@R_hps\@/highest_play_streak/g;
s/\@R_ps\@/play_streak/g;
s/\@A_bss\@/AS best_solve_streak/g;
s/\@A_css\@/AS current_solve_streak/g;
s/\@A_hps\@/AS highest_play_streak/g;
s/\@A_ps\@/AS play_streak/g;
s/\@K_ps\@/'play_streak'/g;
s/\@KV1\@/'play_streak', play_streak/g;
PERL

for fn in "${FUNCS[@]}"; do
  psql "$DB" -tAc "SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname='$fn' AND pronamespace='public'::regnamespace;" \
    | perl -0777 -pe "$PIPE" > "/tmp/fnx/$fn.sql"
done

OUT=supabase-rename-daily-streaks.sql
{
  echo "-- Symmetric daily-streak column rename (internal only; output field names preserved)."
  echo "BEGIN;"
  echo "ALTER TABLE public.profiles RENAME COLUMN play_streak            TO current_daily_play_streak;"
  echo "ALTER TABLE public.profiles RENAME COLUMN highest_play_streak    TO best_daily_play_streak;"
  echo "ALTER TABLE public.profiles RENAME COLUMN current_solve_streak   TO current_daily_solve_streak;"
  echo "ALTER TABLE public.profiles RENAME COLUMN best_solve_streak      TO best_daily_solve_streak;"
  for fn in "${DROP_FIRST[@]}"; do
    args=$(psql "$DB" -tAc "SELECT pg_get_function_identity_arguments(oid) FROM pg_proc WHERE proname='$fn' AND pronamespace='public'::regnamespace;")
    echo "DROP FUNCTION IF EXISTS public.$fn($args);"
  done
  for fn in "${FUNCS[@]}"; do cat "/tmp/fnx/$fn.sql"; echo ";"; done
  echo "COMMIT;"
} > "$OUT"
echo "wrote $OUT"
