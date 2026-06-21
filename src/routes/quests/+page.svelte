<script>
  import { onMount, onDestroy } from 'svelte';
  import { goto } from '$app/navigation';
  import { getDailyQuests, claimQuestReward } from '$lib/stores/statsStore.js';
  import { track } from '$lib/analytics.js';
  import { fx } from '$lib/sound.js';

  /** @type {{ quests:any[], all_done:boolean, reward_claimed:boolean, resets_in_seconds:number }|null} */
  let q = null;
  let loading = true;
  let claiming = false;
  let claimedMsg = '';
  let secs = 0;
  /** @type {ReturnType<typeof setInterval>|undefined} */
  let timer;

  onMount(async () => {
    track('quests_view');
    try { q = await getDailyQuests(); secs = q.resets_in_seconds; }
    finally { loading = false; }
    timer = setInterval(() => { if (secs > 0) secs -= 1; }, 1000);
  });
  onDestroy(() => clearInterval(timer));

  $: countdown = (() => {
    const h = Math.floor(secs / 3600), m = Math.floor((secs % 3600) / 60);
    return h > 0 ? `${h}h ${m}m` : `${m}m`;
  })();
  $: doneCount = q ? q.quests.filter((x) => x.done).length : 0;

  async function claim() {
    if (claiming || !q?.all_done || q?.reward_claimed) return;
    claiming = true;
    const res = await claimQuestReward();
    claiming = false;
    if (res?.ok) {
      track('quest_reward_claimed');
      fx('win');
      claimedMsg = `💰 +$${(res.amount ?? 1000).toLocaleString()} to your Bank!`;
      q = { ...q, reward_claimed: true };
    } else if (res?.reason === 'claimed') {
      q = { ...q, reward_claimed: true };
    }
  }
</script>

<svelte:head><title>WordBank — Daily Quests</title></svelte:head>

<main class="quests-page">
  <button class="back-btn" on:click={() => goto('/')}>← Menu</button>

  {#if loading}
    <p class="loading">Loading…</p>
  {:else if q}
    <div class="head">
      <h1>Daily Quests</h1>
      <span class="resets">resets in {countdown}</span>
    </div>
    <p class="sub">{doneCount}/{q.quests.length} complete · same for everyone today</p>

    <div class="qlist">
      {#each q.quests as quest (quest.id)}
        <div class="quest" class:done={quest.done}>
          <span class="q-emoji">{quest.emoji}</span>
          <div class="q-body">
            <div class="q-top">
              <span class="q-label">{quest.label}</span>
              <span class="q-count">{quest.progress}/{quest.target}{#if quest.done} ✓{/if}</span>
            </div>
            <div class="bar"><div class="fill" style="width:{Math.min(100, (quest.progress / quest.target) * 100)}%"></div></div>
          </div>
        </div>
      {/each}
    </div>

    <div class="reward" class:ready={q.all_done && !q.reward_claimed} class:claimed={q.reward_claimed}>
      {#if q.reward_claimed}
        <span class="r-title">✅ Reward claimed</span>
        <span class="r-sub">{claimedMsg || 'Come back tomorrow for new quests.'}</span>
      {:else if q.all_done}
        <span class="r-title">All quests done! 🎉</span>
        <button class="claim-btn" on:click={claim} disabled={claiming}>
          {claiming ? 'Claiming…' : 'Claim 💰 $1,000'}
        </button>
      {:else}
        <span class="r-title">Finish all 3 to earn 💰 $1,000</span>
        <span class="r-sub">Straight into your Bank.</span>
      {/if}
    </div>
  {/if}
</main>

<style>
  .quests-page { max-width: 460px; margin: 0 auto; padding: 1.5rem 1rem 3rem; }
  .back-btn {
    display: inline-block; margin-bottom: 1.2rem; padding: 0.55rem 1.1rem;
    background: var(--surface); color: var(--text); border: 1px solid var(--border);
    border-radius: 12px; cursor: pointer; font-weight: 600; font-size: 0.9rem;
  }
  .loading { color: var(--text-muted); padding: 2rem; text-align: center; }
  .head { display: flex; align-items: baseline; justify-content: space-between; }
  h1 { font-family: var(--font-display); font-size: 1.7rem; margin: 0; }
  .resets { color: var(--text-faint); font-size: 0.85rem; }
  .sub { color: var(--text-muted); font-size: 0.9rem; margin: 0.2rem 0 1.4rem; }

  .qlist { display: flex; flex-direction: column; gap: 0.7rem; }
  .quest {
    display: flex; gap: 0.9rem; align-items: center; padding: 0.9rem 1rem;
    background: var(--surface); border: 1px solid var(--border); border-radius: 16px;
    transition: border-color 0.2s, background 0.2s;
  }
  .quest.done { border-color: rgba(163, 230, 53, 0.4); background: linear-gradient(135deg, rgba(52,211,153,0.1), rgba(163,230,53,0.04)); }
  .q-emoji { font-size: 1.5rem; width: 40px; height: 40px; display: grid; place-items: center; flex-shrink: 0; }
  .q-body { flex: 1; min-width: 0; }
  .q-top { display: flex; justify-content: space-between; gap: 0.5rem; margin-bottom: 0.5rem; }
  .q-label { font-weight: 600; font-size: 0.98rem; }
  .q-count { font-family: var(--font-display); font-weight: 700; font-size: 0.85rem; color: var(--brand-2); white-space: nowrap; }
  .bar { height: 8px; background: rgba(255,255,255,0.06); border-radius: 999px; overflow: hidden; }
  .fill { height: 100%; background: var(--brand-grad, linear-gradient(90deg,#34d399,#a3e635)); border-radius: 999px; transition: width 0.4s var(--ease-out, ease); }

  .reward {
    margin-top: 1.6rem; padding: 1.1rem; border-radius: 16px; text-align: center;
    display: flex; flex-direction: column; gap: 0.6rem; align-items: center;
    background: var(--surface); border: 1px dashed var(--border);
  }
  .reward.ready { border-style: solid; border-color: rgba(251,191,36,0.5); box-shadow: 0 0 18px rgba(251,191,36,0.2); }
  .reward.claimed { border-color: rgba(163,230,53,0.4); }
  .r-title { font-family: var(--font-display); font-weight: 700; font-size: 1rem; color: var(--text); }
  .r-sub { color: var(--text-muted); font-size: 0.85rem; }
  .claim-btn {
    font-family: var(--font-display); font-weight: 700; font-size: 0.95rem;
    padding: 0.7rem 1.4rem; border: none; border-radius: 999px; cursor: pointer;
    color: #06210f; background: var(--brand-grad, linear-gradient(135deg,#34d399,#a3e635));
  }
  .claim-btn:disabled { opacity: 0.6; cursor: default; }
</style>
