import * as Sentry from '@sentry/sveltekit';
import { handleErrorWithSentry } from '@sentry/sveltekit';

// Client-side error monitoring. Completely inert unless VITE_SENTRY_DSN is set at build time,
// so the app runs identically with or without Sentry configured. The DSN is a public ingest
// key (safe to ship in the client bundle) — see .env.example.
if (import.meta.env.VITE_SENTRY_DSN) {
	Sentry.init({
		dsn: import.meta.env.VITE_SENTRY_DSN,
		environment: import.meta.env.MODE,
		// Errors are always captured; sample a slice of performance traces to keep volume/cost low.
		tracesSampleRate: 0.1
	});
}

// Reports uncaught client errors to Sentry (no-op when the DSN is unset), then falls through
// to SvelteKit's default handling.
export const handleError = handleErrorWithSentry();
