// See https://svelte.dev/docs/kit/types#app.d.ts
// for information about these interfaces.
import type { SupabaseClient, Session } from '@supabase/supabase-js';

declare global {
	namespace App {
		interface Error {
			message: string;
		}
		// Forward-looking: WordBank currently uses Supabase client-side (no hooks.server.ts).
		// These are declared for when/if server-side auth via event.locals is added.
		interface Locals {
			supabase?: SupabaseClient;
			session?: Session | null;
		}
		interface PageData {
			session?: Session | null;
		}
		// interface PageState {}
		// interface Platform {}
	}
}

export {};
