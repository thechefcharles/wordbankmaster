import prettier from 'eslint-config-prettier';
import js from '@eslint/js';
import { includeIgnoreFile } from '@eslint/compat';
import svelte from 'eslint-plugin-svelte';
import globals from 'globals';
import { fileURLToPath } from 'node:url';
import ts from 'typescript-eslint';
const gitignorePath = fileURLToPath(new URL('./.gitignore', import.meta.url));

export default ts.config(
	includeIgnoreFile(gitignorePath),
	// Non-shipped dev artifacts: the REMEMBER scratch dir isn't source.
	{ ignores: ['.remember/**'] },
	js.configs.recommended,
	...ts.configs.recommended,
	...svelte.configs['flat/recommended'],
	prettier,
	...svelte.configs['flat/prettier'],
	{
		languageOptions: {
			globals: {
				...globals.browser,
				...globals.node
			}
		}
	},
	{
		files: ['**/*.svelte'],

		languageOptions: {
			parserOptions: {
				parser: ts.parser
			}
		}
	},
	{
		rules: {
			// Allow intentional throwaways (e.g. `{#each Array(20) as _, i}`) prefixed with `_`.
			'@typescript-eslint/no-unused-vars': [
				'error',
				{
					argsIgnorePattern: '^_',
					varsIgnorePattern: '^_',
					caughtErrorsIgnorePattern: '^_'
				}
			],
			// Our a11y svelte-ignore comments list the full set of related codes for
			// intentional stop-propagation modal wrappers; don't nag when a given element
			// only trips a subset of them.
			'svelte/no-unused-svelte-ignore': 'off'
		}
	},
	{
		// Dev/build scripts are Node CommonJS/ESM tooling, not app source — require() is
		// legit and one-off expression statements (Playwright chains) are fine here.
		files: ['scripts/**'],
		languageOptions: { globals: { ...globals.node } },
		rules: {
			'@typescript-eslint/no-require-imports': 'off',
			'@typescript-eslint/no-unused-expressions': 'off'
		}
	}
);
