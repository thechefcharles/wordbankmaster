<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import PageNav from '$lib/components/PageNav.svelte';
  import { getMyGroups, getGroup } from '$lib/stores/statsStore.js';
  import { fx } from '$lib/sound.js';
  import { track } from '$lib/analytics.js';

  /** @type {any[]} */ let groups = $state([]);
  let loading = $state(true);
  let q = $state('');
  /** @type {string|null} */ let openId = $state(null);
  /** @type {any} */ let openGroup = $state(null);
  let loadingMembers = $state(false);

  onMount(async () => { track('my_groups_view'); try { groups = await getMyGroups(); } finally { loading = false; } });

  let shown = $derived(
    groups
      .filter((g) => (g.name || '').toLowerCase().includes(q.trim().toLowerCase()))
      .sort((a, b) => (a.name || '').localeCompare(b.name || '', undefined, { sensitivity: 'base' }))
  );

  /** @param {any} g */
  async function toggle(g) {
    fx('tap');
    if (openId === g.id) { openId = null; openGroup = null; return; }
    openId = g.id; openGroup = null; loadingMembers = true;
    openGroup = await getGroup(g.id);
    loadingMembers = false;
  }
  const members = (/** @type {any} */ g) => g?.members ?? g?.standings ?? [];
</script>

<svelte:head><title>WordBank — My Groups</title></svelte:head>

<main class="ml-page">
  <PageNav />
  <h1 class="ml-title">My Groups{#if groups.length} · {groups.length}{/if}</h1>

  {#if loading}
    <p class="ml-muted">Loading…</p>
  {:else if groups.length === 0}
    <p class="ml-muted">You're not in any groups yet. Create or join one from <button class="ml-link" onclick={() => goto('/groups')}>Groups</button>.</p>
  {:else}
    <input class="ml-search" type="search" placeholder="Search your groups" bind:value={q} />
    {#if shown.length === 0}
      <p class="ml-muted">No match for “{q}”.</p>
    {:else}
      <div class="ml-list">
        {#each shown as g (g.id)}
          <div class="mg-block">
            <button class="ml-main" onclick={() => toggle(g)}>
              <span class="ml-coin">👥</span>
              <span class="ml-name">{g.name}{#if g.member_count} · {g.member_count}{/if}</span>
              <span class="ml-go">{openId === g.id ? '▾' : '›'}</span>
            </button>
            {#if openId === g.id}
              <div class="mg-members">
                {#if loadingMembers}<p class="ml-muted small">Loading members…</p>
                {:else}
                  {#each members(openGroup) as m}
                    <button class="mg-member" onclick={() => m.username && goto('/u/' + encodeURIComponent(m.username))}>
                      <span class="mg-mname">@{m.username || m.name}{#if m.is_owner} <span class="mg-owner">owner</span>{/if}</span>
                      {#if m.username}<span class="ml-go">›</span>{/if}
                    </button>
                  {/each}
                {/if}
              </div>
            {/if}
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
  .ml-muted.small { padding: 0.6rem 0; font-size: 0.85rem; }
  .ml-link { background: none; border: none; color: var(--brand-2); font: inherit; cursor: pointer; text-decoration: underline; }
  .ml-search { width: 100%; padding: 0.7rem 1rem; border-radius: 12px; border: 1px solid var(--border); background: var(--surface); color: var(--text); font-size: 0.95rem; margin-bottom: 14px; }
  .ml-list { display: flex; flex-direction: column; gap: 8px; }
  .ml-main { width: 100%; display: flex; align-items: center; gap: 12px; padding: 11px 14px; border-radius: 14px; cursor: pointer;
    background: var(--surface); border: 1px solid var(--border); color: var(--text); text-align: left; }
  .ml-main:hover { border-color: var(--brand-2); }
  .ml-coin { width: 36px; height: 36px; flex: none; border-radius: 50%; display: grid; place-items: center; font-size: 1.1rem; background: var(--surface-2, rgba(255,255,255,0.06)); }
  .ml-name { flex: 1; font-weight: 700; font-size: 0.98rem; }
  .ml-go { color: var(--text-faint); }
  .mg-members { display: flex; flex-direction: column; gap: 4px; padding: 6px 0 4px 12px; }
  .mg-member { display: flex; align-items: center; justify-content: space-between; padding: 9px 12px; border-radius: 10px; cursor: pointer;
    background: var(--surface-2, rgba(255,255,255,0.04)); border: 1px solid var(--border); color: var(--text); }
  .mg-member:hover { border-color: var(--brand-2); }
  .mg-mname { font-weight: 600; font-size: 0.9rem; }
  .mg-owner { font-size: 0.66rem; color: var(--gold); margin-left: 4px; }
</style>
