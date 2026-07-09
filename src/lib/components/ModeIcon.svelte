<script>
	/** Game mode: daily | makeup | climb | match | challenge | blitz. */
	export let mode = '';
	/** Pixel size (square). */
	export let size = 18;

	// Shared line-icon attrs; stroke inherits via currentColor so callers set color.
	const A =
		'viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" ' +
		'stroke-linecap="round" stroke-linejoin="round" style="width:100%;height:100%" aria-hidden="true"';

	const CAL = `<svg ${A}><rect x="3.5" y="5" width="17" height="15" rx="2"/><path d="M3.5 9.5h17M8 3v4M16 3v4"/></svg>`;
	const SWORDS = `<svg ${A}><polyline points="14.5 17.5 3 6 3 3 6 3 17.5 14.5"/><line x1="13" y1="19" x2="19" y2="13"/><line x1="16" y1="16" x2="20" y2="20"/><line x1="19" y1="21" x2="21" y2="19"/><polyline points="14.5 6.5 18 3 21 3 21 6 17.5 9.5"/><line x1="5" y1="14" x2="9" y2="18"/><line x1="7" y1="17" x2="4" y2="20"/><line x1="3" y1="19" x2="5" y2="21"/></svg>`;

	/** @type {Record<string,string>} */
	const SVG = {
		daily: CAL,
		makeup: CAL,
		climb: `<svg ${A}><circle cx="12" cy="12" r="8.6"/><path d="M12 7v10"/><path d="M14.6 9.2c-.6-.8-1.6-1.2-2.7-1.2-1.7 0-2.9 1-2.9 2.3s1.3 1.9 2.9 2.2 2.9 1 2.9 2.3-1.3 2.3-2.9 2.3c-1.1 0-2.2-.5-2.8-1.3"/></svg>`,
		match: SWORDS,
		challenge: SWORDS,
		blitz: `<svg ${A}><path d="M13 2 4.5 13.5H11l-1 8.5 8.5-11.5H12z"/></svg>`
	};

	$: html = SVG[mode] ?? '';
</script>

{#if html}
	<!-- SVG strings are hard-coded constants above, never user input. -->
	<!-- eslint-disable-next-line svelte/no-at-html-tags -->
	<span class="mode-ic" style="width:{size}px;height:{size}px">{@html html}</span>
{/if}

<style>
	.mode-ic {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		flex: none;
		line-height: 0;
	}
</style>
