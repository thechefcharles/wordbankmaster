// src/routes/+page.server.js
import { createServerClient } from '@supabase/ssr';
import { cookies } from '@sveltejs/kit';

export const load = async ({ request }) => {
  const supabase = createServerClient(
    'https://YOUR_PROJECT_ID.supabase.co',
    'YOUR_SUPABASE_ANON_KEY',
    {
      cookies: {
        get(name) {
          return request.headers.get('cookie')?.split('; ')
            .find((c) => c.startsWith(`${name}=`))
            ?.split('=')[1];
        }
      }
    }
  );

  const {
    data: { user }
  } = await supabase.auth.getUser();

  return { user };
};
