import { redirect } from '@sveltejs/kit';
import { createServerClient } from '@supabase/ssr';

// OAuth (Google) + magic-link PKCE callback: exchange the ?code for a session.
export const GET = async ({ url, cookies }) => {
  const code = url.searchParams.get('code');
  const next = url.searchParams.get('next') ?? '/';

  // Provider can also bounce back with an error (cancelled, access_denied, etc.).
  const providerError = url.searchParams.get('error_description') || url.searchParams.get('error');
  if (providerError) {
    console.error('OAuth provider error:', providerError);
    return redirect(303, '/?auth_error=' + encodeURIComponent(providerError));
  }

  if (code) {
    const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
    const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;
    if (!supabaseUrl || !supabaseAnonKey) {
      console.error('Missing Supabase env vars on Vercel');
      return redirect(303, '/?auth_error=config');
    }
    const supabase = createServerClient(supabaseUrl, supabaseAnonKey, {
      // getAll/setAll is the chunk-safe API in @supabase/ssr >=0.5 — reads the
      // (possibly chunked) PKCE code-verifier + writes the session cookies.
      cookies: {
        getAll() {
          return cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value, options }) => {
            cookies.set(name, value, {
              ...options,
              path: '/',
              // MUST be JS-readable: the app reads the session with the BROWSER
              // Supabase client (document.cookie). httpOnly here = the session is
              // set but invisible to the app → "No session" after Google sign-in.
              httpOnly: false,
              sameSite: 'lax',
              secure: import.meta.env.PROD
            });
          });
        }
      }
    });

    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) {
      return redirect(303, next);
    }
    console.error('Auth callback exchange error:', error.message);
    return redirect(303, '/?auth_error=exchange&auth_detail=' + encodeURIComponent(error.message));
  }

  return redirect(303, '/?auth_error=nocode');
};
