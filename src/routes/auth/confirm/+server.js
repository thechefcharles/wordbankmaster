import { redirect } from '@sveltejs/kit';
import { createServerClient } from '@supabase/ssr';

// Email-OTP confirmation (password recovery, email change, signup confirm).
// Unlike the PKCE ?code= flow (/auth/callback), verifyOtp with a token_hash
// needs NO local code verifier, so the link works on ANY device — request the
// reset on a laptop, open the email on your phone, and it still completes.
export const GET = async ({ url, cookies }) => {
	const token_hash = url.searchParams.get('token_hash');
	const type = url.searchParams.get('type');
	const next = url.searchParams.get('next') ?? '/';

	if (token_hash && type) {
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
							httpOnly: false, // browser Supabase client must read the session via document.cookie
							sameSite: 'lax',
							secure: import.meta.env.PROD
						});
					},
					remove(name, options) {
						cookies.delete(name, {
							...options,
							path: '/',
							httpOnly: true,
							sameSite: 'lax',
							secure: import.meta.env.PROD
						});
					}
				}
			});

			const { error } = await supabase.auth.verifyOtp({
				type: /** @type {any} */ (type),
				token_hash
			});
			if (!error) {
				return redirect(303, next);
			}
			console.error('Auth confirm error:', error.message);
		} else {
			console.error('Missing Supabase env vars on Vercel');
		}
	}

	// Verification failed → land on the reset page with a clear message.
	return redirect(303, '/reset-password?error_description=Email+link+is+invalid+or+has+expired');
};
