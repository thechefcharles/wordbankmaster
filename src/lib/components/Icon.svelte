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
		key: `<svg ${A}><circle cx="8" cy="15" r="3.4"/><path d="M10.4 12.6L20 3M16.5 6.5l2.2 2.2M14.5 8.5l2 2"/></svg>`
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
