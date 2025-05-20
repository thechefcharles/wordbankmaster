// src/routes/+page.server.js
import { createServerClient } from '@supabase/ssr';

export const load = async ({ cookies }) => {
  const supabase = createServerClient(
    import.meta.env.VITE_SUPABASE_URL,
    import.meta.env.VITE_SUPABASE_ANON_KEY,
    {
      cookies: {
        get(name) {
          return cookies.get(name);
        },
        set(name, value, options) {
          cookies.set(name, value, {
            ...options,
            httpOnly: true,
            sameSite: 'Lax',
            secure: true,
          });
        },
        remove(name, options) {
          cookies.delete(name, {
            ...options,
            httpOnly: true,
            sameSite: 'Lax',
            secure: true,
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
