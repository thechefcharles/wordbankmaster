// Server-side signout: deletes the Supabase auth cookies and redirects home.
// Needed because a legacy httpOnly auth cookie can't be cleared by client JS — only the
// server can delete it. The client bounces here when it detects a stale-session mismatch
// (SSR sees a user, but the browser has no usable session), so the app self-heals to a
// clean login instead of stranding the user.
import { createServerClient } from '@supabase/ssr';
import { redirect } from '@sveltejs/kit';

export const GET = async ({ cookies }) => {
	const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
	const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;
	if (supabaseUrl && supabaseAnonKey) {
		const supabase = createServerClient(supabaseUrl, supabaseAnonKey, {
			cookies: {
				get(name) {
					return cookies.get(name);
				},
				set(name, value, options) {
					cookies.set(name, value, {
						...options,
						path: '/',
						httpOnly: false,
						sameSite: 'lax',
						secure: import.meta.env.PROD
					});
				},
				remove(name, options) {
					cookies.delete(name, {
						...options,
						path: '/',
						httpOnly: false,
						sameSite: 'lax',
						secure: import.meta.env.PROD
					});
				}
			}
		});
		try {
			await supabase.auth.signOut();
		} catch {
			/* ignore — we still purge cookies below */
		}
	}
	// Belt-and-suspenders: delete every Supabase auth cookie by name, including a legacy
	// httpOnly one the client can't touch. Server-side delete matches by name regardless
	// of the httpOnly flag.
	for (const { name } of cookies.getAll()) {
		if (name.startsWith('sb-')) cookies.delete(name, { path: '/' });
	}
	// ?signedout=1 lets the home page's init break the loop if a cookie somehow survives.
	throw redirect(303, '/?signedout=1');
};
