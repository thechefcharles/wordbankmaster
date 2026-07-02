// See https://svelte.dev/docs/kit/types#app.d.ts
// for information about these interfaces
import type { SupabaseClient, Session } from '@supabase/supabase-js';

declare global {
	namespace App {
		interface Error {
			message: string;
		}
		interface Locals {
			supabase: SupabaseClient;
			session: Session | null;
		}
		interface PageData {
			session: Session | null;
		}
		// interface PageState {}
		// interface Platform {}
	}
}

export {};
