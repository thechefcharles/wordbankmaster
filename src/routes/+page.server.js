// src/routes/+page.server.js
import { createServerClient } from '@supabase/ssr';
import { cookies } from '@sveltejs/kit';

export const load = async ({ cookies }) => {
  const supabase = createServerClient(
    import.meta.env.VITE_SUPABASE_URL,
    import.meta.env.VITE_SUPABASE_ANON_KEY,
    { cookies }
  );

  const {
    data: { user }
  } = await supabase.auth.getUser();

  return { user };
};
