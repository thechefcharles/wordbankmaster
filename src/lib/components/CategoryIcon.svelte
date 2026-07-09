<script>
	import { categoryMeta } from '$lib/categories.js';

	/** Category value (emoji may be baked in) or label. */
	export let category = '';
	/** Pixel size (square). */
	export let size = 18;

	// Shared line-icon attrs; stroke inherits via currentColor so callers set color.
	const A =
		'viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" ' +
		'stroke-linecap="round" stroke-linejoin="round" style="width:100%;height:100%" aria-hidden="true"';

	/** @type {Record<string,string>} */
	const SVG = {
		movies: `<svg ${A}><path d="M3 9h18"/><path d="M3.4 9 21 9 19.2 4.6 4.6 4.6Z"/><path d="M8.2 4.7 6.3 9M13 4.7 11.1 9M17.8 4.7 15.9 9"/><rect x="3" y="9" width="18" height="11" rx="1.6"/></svg>`,
		music: `<svg ${A}><path d="M9 17.5V6l9-1.8V15.5"/><circle cx="6.6" cy="17.6" r="2.4"/><circle cx="15.6" cy="15.6" r="2.4"/></svg>`,
		famous: `<svg ${A}><path d="M12 3.6l2.5 5.1 5.6.8-4 3.9.95 5.6L12 16.3 6.9 19l.95-5.6-4-3.9 5.6-.8z"/></svg>`,
		food: `<svg ${A}><path d="M6 3v4a2 2 0 0 0 2 2 2 2 0 0 0 2-2V3"/><path d="M8 9v12"/><path d="M17 21V3c-2.2 1-3.3 4.2-3.3 7.2 0 2 1.2 3.3 3.3 3.3z"/></svg>`,
		travel: `<svg ${A}><path d="M21 3 3 10.5l6 2.4 2.4 6z"/><path d="M21 3 9.4 13"/></svg>`,
		sports: `<svg ${A}><path d="M7 4.2h10v4.8a5 5 0 0 1-10 0z"/><path d="M7 6.2H4.2v.8a3 3 0 0 0 2.8 3M17 6.2h2.8v.8a3 3 0 0 1-2.8 3"/><path d="M12 13.8v2.8M9 20.4h6M10.3 20.4c0-1.9.5-3.8 1.7-3.8s1.7 1.9 1.7 3.8"/></svg>`,
		phrases: `<svg ${A}><path d="M4 5h16a1.2 1.2 0 0 1 1.2 1.2v8.6a1.2 1.2 0 0 1-1.2 1.2H9.5L5.5 20v-3.8H4a1.2 1.2 0 0 1-1.2-1.2V6.2A1.2 1.2 0 0 1 4 5z"/><path d="M8 9.4c0 1-.7 1.7-1.6 1.9M13.4 9.4c0 1-.7 1.7-1.6 1.9"/></svg>`,
		science: `<svg ${A}><path d="M9 3h6"/><path d="M10 3.2v6L5.3 17a1.5 1.5 0 0 0 1.3 2.3h10.8a1.5 1.5 0 0 0 1.3-2.3L14 9.2v-6"/><path d="M7.4 14.2h9.2"/></svg>`,
		books: `<svg ${A}><path d="M12 6.2C10 4.7 6.6 4.7 4 5.4v12.8c2.6-.7 6-.7 8 .8 2-1.5 5.4-1.5 8-.8V5.4c-2.6-.7-6-.7-8 .8z"/><path d="M12 6.2V19"/></svg>`,
		games: `<svg ${A}><rect x="2.5" y="8" width="19" height="9" rx="4.5"/><path d="M6.8 11v3M5.3 12.5h3"/><circle cx="15.8" cy="11.6" r="1"/><circle cx="18.3" cy="13.6" r="1"/></svg>`,
		brands: `<svg ${A}><path d="M11 3.5H4.5A1 1 0 0 0 3.5 4.5V11l8.8 8.8a1.2 1.2 0 0 0 1.7 0l5.8-5.8a1.2 1.2 0 0 0 0-1.7z"/><circle cx="8" cy="8" r="1.3"/></svg>`,
		tech: `<svg ${A}><rect x="5" y="4.8" width="14" height="9.6" rx="1.6"/><path d="M2.5 19h19M3.6 19 5 17h14l1.4 2"/></svg>`
	};

	$: html = SVG[categoryMeta(category)?.icon ?? ''] ?? '';
</script>

{#if html}
	<!-- SVG strings are hard-coded constants (see SVG map above), never user input. -->
	<!-- eslint-disable-next-line svelte/no-at-html-tags -->
	<span class="cat-ic" style="width:{size}px;height:{size}px">{@html html}</span>
{/if}

<style>
	.cat-ic {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		flex: none;
		line-height: 0;
	}
</style>
