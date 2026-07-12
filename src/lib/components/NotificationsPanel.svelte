<script>
	// Your personal notifications inbox (results, sabotages, friend requests,
	// incoming challenges). Shown in Community ▸ Activity. Friend requests can be
	// accepted/declined inline; tapping a row routes via onNavigate.
	import { notifications, dismissNotification } from '$lib/stores/notificationStore.js';
	import { respondFriendRequest, respondJoinRequest } from '$lib/stores/statsStore.js';
	import { fx } from '$lib/sound.js';
	import Icon from '$lib/components/Icon.svelte';

	/** @type {{ onNavigate?: ((n:any)=>void)|null, onChange?: (()=>void)|null }} */
	let { onNavigate = null, onChange = null } = $props();

	/** @param {any} n @param {boolean} accept */
	async function respond(n, accept) {
		const fromId = n?.data?.from_id;
		if (!fromId) return;
		const res = await respondFriendRequest(fromId, accept);
		if (res?.ok) {
			fx(accept ? 'win' : 'tap');
			dismissNotification(n.id); // acting on it clears it
			onChange?.();
		}
	}

	/** @param {any} n @param {boolean} accept */
	async function respondGroup(n, accept) {
		const { group_id, from_id } = n?.data || {};
		if (!group_id || !from_id) return;
		const res = await respondJoinRequest(group_id, from_id, accept);
		if (res?.ok) {
			fx(accept ? 'win' : 'tap');
			dismissNotification(n.id);
			onChange?.();
		}
	}

	// Action-required notifications (friend request / group-join request) must be
	// accepted or declined — they can't be dismissed, and tapping them won't clear them.
	/** @param {any} n */
	const actionRequired = (n) =>
		(n.type === 'friend_request' && n.data?.from_id) ||
		(n.type === 'group_join' && n.data?.group_id && n.data?.from_id);
</script>

{#if $notifications.length === 0}
	<p class="empty">No notifications yet — challenge results, sabotages and requests land here.</p>
{:else}
	<div class="notif-list">
		{#each $notifications as n (n.id)}
			<div class="notif-item" class:fresh={!n.read} class:needs-action={actionRequired(n)}>
				{#if !actionRequired(n)}
					<button
						class="ni-dismiss"
						onclick={() => dismissNotification(n.id)}
						aria-label="Dismiss"
						title="Dismiss"><Icon name="close" size={14} /></button
					>
				{/if}
				<button
					class="ni-main"
					onclick={() => {
						onNavigate?.(n);
						if (!actionRequired(n)) dismissNotification(n.id);
					}}
				>
					<span class="ni-title">{n.title}</span>
					<span class="ni-body">{n.body}</span>
				</button>
				{#if n.type === 'friend_request' && n.data?.from_id}
					<div class="ni-actions">
						<button class="ni-act accept" onclick={() => respond(n, true)}>Accept</button>
						<button class="ni-act decline" onclick={() => respond(n, false)}>Decline</button>
					</div>
				{:else if n.type === 'group_join' && n.data?.group_id && n.data?.from_id}
					<div class="ni-actions">
						<button class="ni-act accept" onclick={() => respondGroup(n, true)}>Approve</button>
						<button class="ni-act decline" onclick={() => respondGroup(n, false)}>Decline</button>
					</div>
				{/if}
			</div>
		{/each}
	</div>
{/if}

<style>
	.empty {
		color: var(--text-muted);
		font-size: 0.88rem;
		text-align: center;
		padding: 1rem 0.4rem;
	}
	.notif-list {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
	}
	.notif-item {
		position: relative;
		padding: 0.7rem 2.1rem 0.7rem 0.85rem;
		border-radius: 12px;
		background: var(--surface);
		border: 1px solid var(--border);
		color: var(--text);
	}
	.notif-item.needs-action {
		padding-right: 0.85rem;
	}
	.ni-dismiss {
		position: absolute;
		top: 6px;
		right: 6px;
		width: 26px;
		height: 26px;
		border-radius: 8px;
		border: none;
		cursor: pointer;
		background: transparent;
		color: var(--text-faint);
		font-size: 0.9rem;
	}
	.ni-dismiss:hover {
		background: var(--surface-2, rgba(255, 255, 255, 0.06));
		color: var(--text);
	}
	.notif-item.fresh {
		border-color: rgba(253, 224, 71, 0.45);
		background: linear-gradient(135deg, rgba(251, 191, 36, 0.08), rgba(253, 224, 71, 0.03));
	}
	.ni-main {
		text-align: left;
		display: flex;
		flex-direction: column;
		gap: 2px;
		width: 100%;
		background: none;
		border: none;
		color: inherit;
		cursor: pointer;
		padding: 0;
	}
	.ni-title {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.92rem;
	}
	.ni-body {
		font-size: 0.82rem;
		color: var(--text-muted);
	}
	.ni-actions {
		display: flex;
		gap: 0.5rem;
		margin-top: 0.55rem;
	}
	.ni-act {
		flex: 1;
		padding: 0.45rem 0.7rem;
		border-radius: 9px;
		font-weight: 800;
		font-size: 0.82rem;
		cursor: pointer;
		border: 1px solid var(--border);
	}
	.ni-act.accept {
		color: #3a2a00;
		border: none;
		background: var(--brand-grad, linear-gradient(135deg, #fbbf24, #fde047));
	}
	.ni-act.decline {
		color: #f87171;
		background: transparent;
		border-color: rgba(248, 113, 113, 0.4);
	}
</style>
