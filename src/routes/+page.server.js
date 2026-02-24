// src/routes/+page.server.js
import { createServerClient } from '@supabase/ssr';

export const load = async ({ cookies }) => {
  const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
  const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;
  if (!supabaseUrl || !supabaseAnonKey) {
    console.error('Missing VITE_SUPABASE_URL or VITE_SUPABASE_ANON_KEY on Vercel. Add them in Project Settings → Environment Variables.');
    return { user: null };
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
            secure: import.meta.env.PROD, // false in dev so cookies persist on http://localhost
          });
        },
        remove(name, options) {
          cookies.delete(name, {
            ...options,
            httpOnly: true,
            sameSite: 'lax',
            secure: import.meta.env.PROD,
          });
        }
      }
    }
  );

  const {
    data: { user }
  } = await supabase.auth.getUser();

  return { user };
};
