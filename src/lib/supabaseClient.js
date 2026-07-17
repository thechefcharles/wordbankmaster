// Supabase client — localStorage session (client-only SPA).
//
// Uses createClient (not @supabase/ssr's createBrowserClient) because the app is a client-side
// SPA that bundles into the native iOS app: the session must live in localStorage, which works
// identically in a browser and the Capacitor WebView. There is no server to share a cookie with.
//
// detectSessionInUrl handles the OAuth ?code / recovery token on load, so no server callback
// route is needed. flowType 'pkce' matches how signInWithOAuth is initiated client-side.
//
// NOTE: this is why every logged-in user is signed out exactly once on the cutover — old
// sessions lived in cookies (createBrowserClient); the client now looks in localStorage.
import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
	auth: {
		persistSession: true,
		autoRefreshToken: true,
		detectSessionInUrl: true,
		flowType: 'pkce'
	}
});
