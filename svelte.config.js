import adapter from '@sveltejs/adapter-vercel';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

/** @type {import('@sveltejs/kit').Config} */
const config = {
    preprocess: vitePreprocess(),

    kit: {
        adapter: adapter(),
        env: {
            dir: process.cwd(),
            publicPrefix: 'VITE_'  // Ensures Vite environment variables are read
        }
    }
};

export default config;
