<script>
	/** Named line icon — see the SVG map below for available names. */
	export let name = '';
	/** Pixel size (square). */
	export let size = 18;

	// Shared line-icon attrs; stroke inherits via currentColor so callers set color.
	// Matches ModeIcon/CategoryIcon so the whole set reads as one family.
	const A =
		'viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" ' +
		'stroke-linecap="round" stroke-linejoin="round" style="width:100%;height:100%" aria-hidden="true"';
	const DOT = 'fill="currentColor" stroke="none"';

	/** @type {Record<string,string>} */
	const SVG = {
		// ── sound / haptics / music ──────────────────────────────────────────────
		volume: `<svg ${A}><path d="M4 9.5v5h3.5L12 18V6L7.5 9.5z"/><path d="M15.5 9a4 4 0 0 1 0 6"/><path d="M18 6.5a7.5 7.5 0 0 1 0 11"/></svg>`,
		'volume-low': `<svg ${A}><path d="M4 9.5v5h3.5L12 18V6L7.5 9.5z"/><path d="M15.5 9.5a3.5 3.5 0 0 1 0 5"/></svg>`,
		mute: `<svg ${A}><path d="M4 9.5v5h3.5L12 18V6L7.5 9.5z"/><path d="M16 9.5l5 5M21 9.5l-5 5"/></svg>`,
		vibrate: `<svg ${A}><rect x="8.5" y="5" width="7" height="14" rx="1.5"/><path d="M4 9v6M20 9v6"/></svg>`,
		'vibrate-off': `<svg ${A}><rect x="8.5" y="5" width="7" height="14" rx="1.5"/><path d="M4.5 4.5l15 15"/></svg>`,
		music: `<svg ${A}><path d="M9 17V5l10-2v12"/><circle cx="6.5" cy="17" r="2.5"/><circle cx="16.5" cy="15" r="2.5"/></svg>`,

		// ── nav / controls ───────────────────────────────────────────────────────
		menu: `<svg ${A}><path d="M4 7h16M4 12h16M4 17h16"/></svg>`,
		close: `<svg ${A}><path d="M6 6l12 12M18 6L6 18"/></svg>`,
		check: `<svg ${A}><polyline points="4 12.5 9.5 18 20 6"/></svg>`,
		'chevron-left': `<svg ${A}><polyline points="15 6 9 12 15 18"/></svg>`,
		'chevron-right': `<svg ${A}><polyline points="9 6 15 12 9 18"/></svg>`,
		play: `<svg ${A}><path d="M8 5.5v13l11-6.5z"/></svg>`,
		'give-up': `<svg ${A}><path d="M14 4h3a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-3"/><polyline points="9 8 5 12 9 16"/><path d="M5 12h10"/></svg>`,
		settings: `<svg ${A}><circle cx="12" cy="12" r="3.2"/><path d="M12 2.5v3.2M12 18.3v3.2M4.2 7l2.8 1.6M17 15.4l2.8 1.6M4.2 17l2.8-1.6M17 8.6l2.8-1.6"/></svg>`,
		search: `<svg ${A}><circle cx="11" cy="11" r="6"/><path d="M20 20l-4.3-4.3"/></svg>`,
		trash: `<svg ${A}><path d="M4 7h16M9.5 7V4.5h5V7M6.5 7l1 12.5h9L17.5 7"/></svg>`,
		edit: `<svg ${A}><path d="M4 20h4L18.5 9.5l-4-4L4 16z"/><path d="M13.5 6.5l4 4"/></svg>`,
		bell: `<svg ${A}><path d="M6 16.5V11a6 6 0 0 1 12 0v5.5l1.5 2h-15z"/><path d="M10 21a2 2 0 0 0 4 0"/></svg>`,
		info: `<svg ${A}><circle cx="12" cy="12" r="9"/><path d="M12 11v5.5"/><circle cx="12" cy="7.8" r="0.7" ${DOT}/></svg>`,
		help: `<svg ${A}><circle cx="12" cy="12" r="9"/><path d="M9.4 9.6a2.6 2.6 0 1 1 3.6 2.4c-.8.4-1 .9-1 1.7"/><circle cx="12" cy="16.8" r="0.7" ${DOT}/></svg>`,
		home: `<svg ${A}><path d="M4 11l8-6 8 6"/><path d="M6.5 10v9.5h11V10"/></svg>`,
		user: `<svg ${A}><circle cx="12" cy="8" r="3.5"/><path d="M5 20c0-3.6 3.1-6 7-6s7 2.4 7 6"/></svg>`,
		share: `<svg ${A}><path d="M12 15V4.5M8 8l4-4 4 4"/><path d="M6 12v7.5h12V12"/></svg>`,
		refresh: `<svg ${A}><path d="M4.5 12a7.5 7.5 0 0 1 12.8-5.3L20 9M20 4.5V9h-4.5"/><path d="M19.5 12a7.5 7.5 0 0 1-12.8 5.3L4 15M4 19.5V15h4.5"/></svg>`,
		link: `<svg ${A}><path d="M10.5 13.5a3.5 3.5 0 0 0 5 .3l2-2a3.5 3.5 0 0 0-5-5l-1 1"/><path d="M13.5 10.5a3.5 3.5 0 0 0-5-.3l-2 2a3.5 3.5 0 0 0 5 5l1-1"/></svg>`,
		lock: `<svg ${A}><rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/></svg>`,
		unlock: `<svg ${A}><rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 7.5-2"/></svg>`,
		key: `<svg ${A}><circle cx="8" cy="15" r="3.4"/><path d="M10.4 12.6L20 3M16.5 6.5l2.2 2.2M14.5 8.5l2 2"/></svg>`,

		// ── money / economy ─────────────────────────────────────────────────────
		cash: `<svg ${A}><rect x="3" y="6.5" width="18" height="11" rx="2"/><circle cx="12" cy="12" r="2.6"/><path d="M6.5 9.5v5M17.5 9.5v5"/></svg>`,
		card: `<svg ${A}><rect x="3" y="5.5" width="18" height="13" rx="2.5"/><path d="M3 10h18"/><path d="M6.5 14.5h4"/></svg>`,
		bank: `<svg ${A}><path d="M3.5 9.5L12 4l8.5 5.5"/><path d="M5.5 10v7M9.5 10v7M14.5 10v7M18.5 10v7"/><path d="M3.5 20h17"/></svg>`,
		coin: `<svg ${A}><circle cx="12" cy="12" r="8"/><path d="M12 7.5v9"/><path d="M14.3 9.4a2.4 2.4 0 0 0-2.3-1.2c-1.4 0-2.3.8-2.3 1.8 0 2.3 4.6 1.3 4.6 3.6 0 1-1 1.8-2.3 1.8a2.5 2.5 0 0 1-2.3-1.3"/></svg>`,
		broke: `<svg ${A}><rect x="3.5" y="8" width="12.5" height="9" rx="2"/><circle cx="9.7" cy="12.5" r="2"/><path d="M18.5 8.5l2.5-1M18.5 12.5H21M18.5 16.5l2.5 1"/></svg>`,
		receipt: `<svg ${A}><path d="M6 3.5h12v17l-2-1.4-2 1.4-2-1.4-2 1.4-2-1.4V3.5z"/><path d="M9 8h6M9 11h6M9 14h4"/></svg>`,
		gem: `<svg ${A}><path d="M6 4h12l3 5-9 11L3 9z"/><path d="M3 9h18M9 4l-2 5 5 11 5-11-2-5"/></svg>`,
		growth: `<svg ${A}><path d="M4 4v16h16"/><polyline points="7 14.5 11 10 14 13 19.5 6.5"/><polyline points="19.5 6.5 19.5 10.5 15.5 6.5"/></svg>`,
		exchange: `<svg ${A}><path d="M4 8h13M14 5l3 3-3 3"/><path d="M20 16H7M10 13l-3 3 3 3"/></svg>`,

		// ── ranks / awards ──────────────────────────────────────────────────────
		trophy: `<svg ${A}><path d="M8 4.5h8v4.5a4 4 0 0 1-8 0z"/><path d="M8 5.5H5.5v1a3 3 0 0 0 3 3M16 5.5h2.5v1a3 3 0 0 1-3 3"/><path d="M12 13v3.5M9 20h6M10 20l.5-3.5M14 20l-.5-3.5"/></svg>`,
		medal: `<svg ${A}><circle cx="12" cy="14.5" r="5"/><path d="M8.5 10L6 3.5M15.5 10L18 3.5M9 3.5h6"/><path d="M12 12.5v4M10.2 14.5h3.6"/></svg>`,
		badge: `<svg ${A}><circle cx="12" cy="9" r="5"/><path d="M8.7 13L7 21l5-2.6L17 21l-1.7-8"/></svg>`,
		crown: `<svg ${A}><path d="M4 8l3.2 3L12 5l4.8 6L20 8l-1.6 9.5H5.6z"/></svg>`,
		target: `<svg ${A}><circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="4.4"/><circle cx="12" cy="12" r="1" ${DOT}/></svg>`,
		fire: `<svg ${A}><path d="M12 3.5c.8 2.8 3.6 3.8 3.6 7.3a3.6 3.6 0 0 1-7.2 0c0-1.4.7-2.3 1.2-3 .6 1 1.5 1.1 1.7 1.9.5-1.7-.6-3-.9-4 .6.3 1.2.5 1.6-.1z"/></svg>`,

		// ── power-ups / buffs ────────────────────────────────────────────────────
		shield: `<svg ${A}><path d="M12 3.5l7 2.8v4.7c0 4.7-3 7.6-7 9.5-4-1.9-7-4.8-7-9.5V6.3z"/></svg>`,
		skip: `<svg ${A}><path d="M5.5 5.5l8 6.5-8 6.5z"/><path d="M17 5.5v13"/></svg>`,
		eye: `<svg ${A}><path d="M2.5 12S6 6.5 12 6.5 21.5 12 21.5 12 18 17.5 12 17.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="2.6"/></svg>`,
		bulb: `<svg ${A}><path d="M9.5 18h5M10 21h4"/><path d="M12 3a6 6 0 0 1 3.8 10.6c-.6.5-.8 1.1-.8 2.4H9c0-1.3-.2-1.9-.8-2.4A6 6 0 0 1 12 3z"/></svg>`,
		book: `<svg ${A}><path d="M12 6.5C10 5 7 4.5 4 5v13c3-.5 6 0 8 1.5M12 6.5C14 5 17 4.5 20 5v13c-3-.5-6 0-8 1.5M12 6.5v13"/></svg>`,
		tag: `<svg ${A}><path d="M4 4.5h7l9 9-6.5 6.5-9-9z"/><circle cx="8.3" cy="8.3" r="1.4"/></svg>`,
		'letter-a': `<svg ${A}><path d="M6 20l6-15 6 15M8.6 14.5h6.8"/></svg>`,
		boost: `<svg ${A}><path d="M12 3.5v4M12 16.5v4M3.5 12h4M16.5 12h4M6 6l2.6 2.6M15.4 15.4L18 18M18 6l-2.6 2.6M8.6 15.4L6 18"/></svg>`,

		// ── sabotage / debuffs ───────────────────────────────────────────────────
		sabotage: `<svg ${A}><circle cx="11" cy="15" r="6"/><path d="M14.5 10.5l2.5-2.5M16.5 5.5l1 1 1-1M18.5 7.5l1-1"/></svg>`,
		fog: `<svg ${A}><path d="M4 8.5h13M6 12.5h14M4 16.5h12"/></svg>`,
		toll: `<svg ${A}><path d="M4 8h16v5H4z"/><path d="M4 8l16 5M20 8L4 13"/><path d="M6.5 13v6M17.5 13v6"/></svg>`,
		block: `<svg ${A}><circle cx="12" cy="12" r="8"/><path d="M6.5 6.5l11 11"/></svg>`,
		percent: `<svg ${A}><circle cx="7.5" cy="7.5" r="2.2"/><circle cx="16.5" cy="16.5" r="2.2"/><path d="M6 18L18 6"/></svg>`,

		// ── social / alerts ──────────────────────────────────────────────────────
		users: `<svg ${A}><circle cx="9" cy="9" r="3.2"/><path d="M3.5 19c0-3.1 2.5-5 5.5-5s5.5 1.9 5.5 5"/><path d="M16 6.3a3.2 3.2 0 0 1 0 5.9M17.5 14.2c1.8.6 3 2.1 3 4.8"/></svg>`,
		chat: `<svg ${A}><path d="M4 5h16v11H9l-4 4z"/></svg>`,
		handshake: `<svg ${A}><path d="M11 8l-2.5 2.5a1.4 1.4 0 0 0 2 2l.8-.8.9.9a1.4 1.4 0 0 0 2-2"/><path d="M3 8.5l4-2.5 4 3M21 8.5l-4-2.5-3 2.2"/></svg>`,
		hand: `<svg ${A}><path d="M9 12V6.5a1.4 1.4 0 0 1 2.8 0V11M11.8 11V5.5a1.4 1.4 0 0 1 2.8 0V11M14.6 10.5a1.4 1.4 0 0 1 2.8 0v3.5a6 6 0 0 1-6 6 5 5 0 0 1-4-2l-2.6-3.5a1.4 1.4 0 0 1 2.2-1.7L9 12"/></svg>`,
		siren: `<svg ${A}><path d="M6.5 18v-4.5a5.5 5.5 0 0 1 11 0V18M5 18h14M12 4.5V2.5M9.5 4l-1-1.6M14.5 4l1-1.6"/></svg>`,
		warning: `<svg ${A}><path d="M12 4L2.8 19.5h18.4z"/><path d="M12 10v4.2"/><circle cx="12" cy="17" r="0.7" ${DOT}/></svg>`,
		skull: `<svg ${A}><path d="M5.5 12.5a6.5 6.5 0 1 1 13 0v2.8l-1.5 1v2.4h-10v-2.4l-1.5-1z"/><circle cx="9.5" cy="12.5" r="1.4" ${DOT}/><circle cx="14.5" cy="12.5" r="1.4" ${DOT}/></svg>`,
		'external-link': `<svg ${A}><path d="M14 5h5v5M19 5l-8.5 8.5"/><path d="M17 13.5V18a1.5 1.5 0 0 1-1.5 1.5H6A1.5 1.5 0 0 1 4.5 18V8.5A1.5 1.5 0 0 1 6 7h4.5"/></svg>`,
		timer: `<svg ${A}><circle cx="12" cy="13.5" r="7.5"/><path d="M12 13.5V9M9.5 2.5h5M18.5 6.5l1.5-1.5"/></svg>`,
		door: `<svg ${A}><path d="M6 20h12M8 20V4h8v16"/><circle cx="13.5" cy="12" r="0.9" ${DOT}/></svg>`,

		// ── achievements / misc ─────────────────────────────────────────────────
		calendar: `<svg ${A}><rect x="3.5" y="5" width="17" height="15" rx="2"/><path d="M3.5 9.5h17M8 3v4M16 3v4"/></svg>`,
		swords: `<svg ${A}><polyline points="14.5 17.5 3 6 3 3 6 3 17.5 14.5"/><line x1="13" y1="19" x2="19" y2="13"/><line x1="16" y1="16" x2="20" y2="20"/><polyline points="14.5 6.5 18 3 21 3 21 6 17.5 9.5"/><line x1="5" y1="14" x2="9" y2="18"/><line x1="7" y1="17" x2="4" y2="20"/></svg>`,
		rocket: `<svg ${A}><path d="M12 3c3 1.4 5 4.5 5 8.5L14 15h-4l-3-3.5C7 7.5 9 4.4 12 3z"/><circle cx="12" cy="10" r="1.6"/><path d="M9.5 15l-2.5 4.5M14.5 15l2.5 4.5M10 19.5h4"/></svg>`,
		shark: `<svg ${A}><path d="M14 17c-.5-5 2.5-9.5 6.5-11.5-1 4.3-1.3 8.4-2.5 11.5"/><path d="M3 18.5c2.6 0 3.6-1.2 6-1.2s3.4 1.2 6 1.2 3-1 3-1"/></svg>`,
		drop: `<svg ${A}><path d="M12 3.2c3 4 5 6.6 5 9.8a5 5 0 0 1-10 0c0-3.2 2-5.8 5-9.8z"/></svg>`,
		sprout: `<svg ${A}><path d="M12 20.5V12"/><path d="M12 13c0-3-2.2-5-5.2-5 0 3 2.2 5 5.2 5z"/><path d="M12 11c0-2.6 2.2-4.6 5.2-4.6 0 2.6-2.2 4.6-5.2 4.6z"/></svg>`,
		bolt: `<svg ${A}><path d="M13 2 5 13.5h6l-1 8.5 8.5-11.5H12z"/></svg>`,
		star: `<svg ${A}><path d="M12 3.5l2.7 5.4 6 .9-4.3 4.2 1 6-5.4-2.8-5.4 2.8 1-6L5.3 9.8l6-.9z"/></svg>`
	};

	$: html = SVG[name] ?? '';
</script>

{#if html}
	<!-- SVG strings are hard-coded constants above, never user input. -->
	<!-- eslint-disable-next-line svelte/no-at-html-tags -->
	<span class="line-ic" style="width:{size}px;height:{size}px">{@html html}</span>
{/if}

<style>
	.line-ic {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		flex: none;
		line-height: 0;
		vertical-align: middle;
	}
</style>
