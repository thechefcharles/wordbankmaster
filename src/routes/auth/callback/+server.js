import { redirect } from '@sveltejs/kit';
import { createServerClient } from '@supabase/ssr';

export const GET = async ({ url, cookies }) => {
  const code = url.searchParams.get('code');
  const next = url.searchParams.get('next') ?? '/';

  if (code) {
    const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
    const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;
    if (!supabaseUrl || !supabaseAnonKey) {
      console.error('Missing Supabase env vars on Vercel');
      return redirect(303, '/');
    }
    const supabase = createServerClient(
      supabaseUrl,
      supabaseAnonKey,
      {
        cookies: {
          get(name) {
            return cookies.get(name);
          },
          set(name, value, options) {
            cookies.set(name, value, {
              ...options,
              httpOnly: true,
              sameSite: 'lax',
              secure: import.meta.env.PROD
            });
          },
          remove(name, options) {
            cookies.delete(name, {
              ...options,
              httpOnly: true,
              sameSite: 'lax',
              secure: import.meta.env.PROD
            });
          }
        }
      }
    );

    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) {
      return redirect(303, next);
    }
    console.error('Auth callback error:', error.message);
  }

  return redirect(303, '/');
};
