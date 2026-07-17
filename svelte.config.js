import adapterVercel from '@sveltejs/adapter-vercel';
import adapterStatic from '@sveltejs/adapter-static';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

// Two build targets from one codebase:
//   default            → adapter-vercel (the web deploy + the remote-URL dev shell)
//   BUILD_TARGET=static → adapter-static SPA, for bundling into the native iOS app
// The app is fully client-side (ssr=false, localStorage auth, no server routes), so the
// static build is a pure SPA. `fallback` serves the client shell for every route.
// The committed DEFAULT stays Vercel — flipping to the bundled build is one env var.
const useStatic = process.env.BUILD_TARGET === 'static';

/** @type {import('@sveltejs/kit').Config} */
const config = {
	preprocess: vitePreprocess(),

	kit: {
		adapter: useStatic
			? // fallback: index.html so Capacitor finds the SPA entry (webDir/index.html) directly.
				adapterStatic({ fallback: 'index.html', strict: false })
			: adapterVercel(),
		env: {
			dir: process.cwd(),
			publicPrefix: 'VITE_' // Ensures Vite environment variables are read
		}
	}
};

export default config;
