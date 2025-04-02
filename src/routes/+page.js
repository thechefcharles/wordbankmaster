// src/routes/+page.js
import { supabase } from '$lib/supabaseClient';

export const load = async ({ fetch, session }) => {
  const {
    data: { user }
  } = await supabase.auth.getUser();


  return { user };
};
