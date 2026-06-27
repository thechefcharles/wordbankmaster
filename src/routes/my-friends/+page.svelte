<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import PageNav from '$lib/components/PageNav.svelte';
  import { listFriends, removeFriend } from '$lib/stores/statsStore.js';
  import { requireConfirm } from '$lib/confirm.js';
  import { fx } from '$lib/sound.js';
  import { track } from '$lib/analytics.js';

  /** @type {any[]} */ let friends = $state([]);
  let loading = $state(true);
  let q = $state('');
  let busy = $state('');

  onMount(async () => { track('my_friends_view'); try { friends = await listFriends(); } finally { loading = false; } });

  let shown = $derived(
    friends
      .filter((f) => (f.name || f.username || '').toLowerCase().includes(q.trim().toLowerCase()))
      .sort((a, b) => (a.username || a.name || '').localeCompare(b.username || b.name || '', undefined, { sensitivity: 'base' }))
  );

  /** @param {any} f */
  async function remove(f) {
    if (busy) return;
    if (!(await requireConfirm({ title: 'Remove friend?', message: `Remove @${f.username || f.name} from your friends?`, confirmText: 'Remove', danger: true }))) return;
    busy = f.id;
    await removeFriend(f.id);
    friends = friends.filter((x) => x.id !== f.id);
    busy = '';
    fx('tap');
  }
  /** @param {any} f */
  const initial = (f) => (f.name || f.username || '?').slice(0, 1).toUpperCase();
</script>

<svelte:head><title>WordBank — My Friends</title></svelte:head>

<main class="ml-page">
  <PageNav />
  <h1 class="ml-title">My Friends{#if friends.length} · {friends.length}{/if}</h1>

  {#if loading}
    <p class="ml-muted">Loading…</p>
  {:else if friends.length === 0}
    <p class="ml-muted">No friends yet. Add some from <button class="ml-link" onclick={() => goto('/?people=1')}>Friends & Groups</button>.</p>
  {:else}
    <input class="ml-search" type="search" placeholder="Search your friends" bind:value={q} />
    {#if shown.length === 0}
      <p class="ml-muted">No match for “{q}”.</p>
    {:else}
      <div class="ml-list">
        {#each shown as f (f.id)}
          <div class="ml-row">
            <button class="ml-main" onclick={() => goto('/u/' + encodeURIComponent(f.username || ''))}>
              <span class="ml-coin" style={f.color ? `--c:${f.color}` : ''}>{initial(f)}</span>
              <span class="ml-name">@{f.username || f.name}</span>
              <span class="ml-go">›</span>
            </button>
            <button class="ml-rm" disabled={busy === f.id} onclick={() => remove(f)} title="Remove friend" aria-label="Remove friend">✕</button>
          </div>
        {/each}
      </div>
    {/if}
  {/if}
</main>

<style>
  .ml-page { max-width: 520px; margin: 0 auto; padding: 16px 14px 60px; }
  .ml-title { font-family: var(--font-display); font-size: 1.4rem; margin: 4px 0 14px; }
  .ml-muted { color: var(--text-muted); padding: 1.5rem 0; text-align: center; }
  .ml-link { background: none; border: none; color: var(--brand-2); font: inherit; cursor: pointer; text-decoration: underline; }
  .ml-search { width: 100%; padding: 0.7rem 1rem; border-radius: 12px; border: 1px solid var(--border); background: var(--surface); color: var(--text); font-size: 0.95rem; margin-bottom: 14px; }
  .ml-list { display: flex; flex-direction: column; gap: 8px; }
  .ml-row { display: flex; align-items: center; gap: 8px; }
  .ml-main { flex: 1; display: flex; align-items: center; gap: 12px; padding: 11px 14px; border-radius: 14px; cursor: pointer;
    background: var(--surface); border: 1px solid var(--border); color: var(--text); text-align: left; }
  .ml-main:hover { border-color: var(--brand-2); }
  .ml-coin { width: 36px; height: 36px; flex: none; border-radius: 50%; display: grid; place-items: center; font-family: var(--font-display); font-weight: 800; color: #3a2a00;
    background: linear-gradient(135deg, var(--c, #fde047), #f59e0b); }
  .ml-name { flex: 1; font-weight: 700; font-size: 0.98rem; }
  .ml-go { color: var(--text-faint); }
  .ml-rm { width: 40px; height: 40px; flex: none; border-radius: 12px; cursor: pointer; font-size: 0.9rem;
    background: rgba(248,113,113,0.1); color: #f87171; border: 1px solid rgba(248,113,113,0.4); }
  .ml-rm:hover { background: rgba(248,113,113,0.2); }
  .ml-rm:disabled { opacity: 0.5; }
</style>
