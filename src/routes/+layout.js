// Client-side SPA: no server rendering.
//
// WordBank is being made bundling-ready for the native iOS app (App Store review flags apps
// that load remote content via server.url). A bundled build is a static export, which can't
// contain server routes — so auth moves fully client-side (localStorage sessions), and the
// app renders on the client only. The app already re-checks the Supabase session in onMount,
// so nothing is lost by dropping SSR. Keeping this at the root applies it to every route.
export const ssr = false;

// Let SvelteKit prerender the empty client shell (needed for a static/SPA fallback later).
export const prerender = false;
export const csr = true;
