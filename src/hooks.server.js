import * as Sentry from '@sentry/sveltekit';
import { handleErrorWithSentry, sentryHandle } from '@sentry/sveltekit';
import { sequence } from '@sveltejs/kit/hooks';

// Server-side error monitoring (SSR loads + server routes, running in Vercel functions).
// Inert unless VITE_SENTRY_DSN is set at build time — same convention as VITE_SUPABASE_URL.
if (import.meta.env.VITE_SENTRY_DSN) {
	Sentry.init({
		dsn: import.meta.env.VITE_SENTRY_DSN,
		environment: import.meta.env.MODE,
		tracesSampleRate: 0.1
	});
}

// sentryHandle() is a passthrough request wrapper (adds request context to captured errors);
// it does not change auth or routing behaviour.
export const handle = sequence(sentryHandle());

// Reports uncaught server errors to Sentry (no-op when the DSN is unset).
export const handleError = handleErrorWithSentry();
