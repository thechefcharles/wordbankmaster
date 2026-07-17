// APNs push sender.
//
// Invoked by:
//   1. the DB trigger on `notifications` INSERT (so every _notify() gets push for free), and
//   2. pg_cron retention jobs.
//
// Signs an ES256 JWT with the APNs auth key (.p8, stored as the APNS_KEY secret — never in git).
// Postgres can't do ES256, which is why this lives in an Edge Function.
//
// Auth: callers must present x-push-secret === PUSH_HOOK_SECRET, so the public can't spam it.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const APNS_KEY = Deno.env.get('APNS_KEY')!; // .p8 PEM
const APNS_KEY_ID = Deno.env.get('APNS_KEY_ID')!;
const APNS_TEAM_ID = Deno.env.get('APNS_TEAM_ID')!;
const APNS_BUNDLE_ID = Deno.env.get('APNS_BUNDLE_ID')!;
const HOOK_SECRET = Deno.env.get('PUSH_HOOK_SECRET')!;
// Auto-injected by Supabase into every Edge Function:
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

/** base64url, no padding — JWT + APNs signature encoding. */
function b64url(input: ArrayBuffer | Uint8Array): string {
	const bytes = input instanceof Uint8Array ? input : new Uint8Array(input);
	let bin = '';
	for (const b of bytes) bin += String.fromCharCode(b);
	return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/** Strip the PEM armor and decode to raw PKCS#8 DER for Web Crypto. */
function pemToPkcs8(pem: string): Uint8Array {
	const b64 = pem
		.replace(/-----BEGIN PRIVATE KEY-----/, '')
		.replace(/-----END PRIVATE KEY-----/, '')
		.replace(/\s+/g, '');
	return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

// APNs requires a fresh-ish token but rejects regeneration more than once every 20 min.
// Cache per isolate and refresh well inside APNs' 1-hour validity window.
let cachedJwt: { token: string; iat: number } | null = null;
async function apnsJwt(): Promise<string> {
	const now = Math.floor(Date.now() / 1000);
	if (cachedJwt && now - cachedJwt.iat < 2400) return cachedJwt.token;
	const key = await crypto.subtle.importKey(
		'pkcs8',
		pemToPkcs8(APNS_KEY),
		{ name: 'ECDSA', namedCurve: 'P-256' },
		false,
		['sign']
	);
	const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: 'ES256', kid: APNS_KEY_ID })));
	const payload = b64url(new TextEncoder().encode(JSON.stringify({ iss: APNS_TEAM_ID, iat: now })));
	const signingInput = `${header}.${payload}`;
	// Web Crypto returns the raw r||s signature, which is exactly what JWS ES256 wants.
	const sig = await crypto.subtle.sign(
		{ name: 'ECDSA', hash: 'SHA-256' },
		key,
		new TextEncoder().encode(signingInput)
	);
	const token = `${signingInput}.${b64url(sig)}`;
	cachedJwt = { token, iat: now };
	return token;
}

const hostFor = (env: string) =>
	env === 'production' ? 'api.push.apple.com' : 'api.sandbox.push.apple.com';

async function sendOne(deviceToken: string, env: string, payload: unknown, jwt: string) {
	return await fetch(`https://${hostFor(env)}/3/device/${deviceToken}`, {
		method: 'POST',
		headers: {
			authorization: `bearer ${jwt}`,
			'apns-topic': APNS_BUNDLE_ID,
			'apns-push-type': 'alert',
			'apns-priority': '10'
		},
		body: JSON.stringify(payload)
	});
}

Deno.serve(async (req) => {
	if (req.headers.get('x-push-secret') !== HOOK_SECRET) {
		return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401 });
	}

	let input: {
		user_id?: string;
		title?: string;
		body?: string;
		data?: Record<string, unknown>;
		badge?: number;
	};
	try {
		input = await req.json();
	} catch {
		return new Response(JSON.stringify({ error: 'bad_json' }), { status: 400 });
	}
	const { user_id, title, body, data = {}, badge } = input;
	if (!user_id || !title) {
		return new Response(JSON.stringify({ error: 'missing user_id/title' }), { status: 400 });
	}

	const supabase = createClient(SUPABASE_URL, SERVICE_KEY);
	const { data: tokens, error } = await supabase
		.from('device_tokens')
		.select('token, env')
		.eq('user_id', user_id);
	if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 });
	if (!tokens?.length) return new Response(JSON.stringify({ sent: 0, reason: 'no_tokens' }));

	const jwt = await apnsJwt();
	const payload = {
		aps: {
			alert: { title, body: body ?? '' },
			sound: 'default',
			...(badge != null ? { badge } : {})
		},
		...data
	};

	let sent = 0;
	const failures: string[] = [];
	for (const t of tokens) {
		const env = t.env ?? 'sandbox';
		let res = await sendOne(t.token, env, payload, jwt);

		// A dev token hit against production (or vice versa) returns 400 BadDeviceToken.
		// Retry the other environment and remember which one worked — self-heals the
		// dev-build -> TestFlight transition without re-registering.
		if (res.status === 400) {
			const err = await res.json().catch(() => ({}) as Record<string, unknown>);
			if (err?.reason === 'BadDeviceToken') {
				const other = env === 'production' ? 'sandbox' : 'production';
				res = await sendOne(t.token, other, payload, jwt);
				if (res.ok) {
					await supabase
						.from('device_tokens')
						.update({ env: other })
						.eq('user_id', user_id)
						.eq('token', t.token);
				}
			}
		}

		// 410 Gone = the app was uninstalled / token dead. Prune it.
		if (res.status === 410) {
			await supabase.from('device_tokens').delete().eq('user_id', user_id).eq('token', t.token);
			continue;
		}
		if (res.ok) sent++;
		else failures.push(`${res.status}:${await res.text().catch(() => '')}`.slice(0, 120));
	}

	return new Response(JSON.stringify({ sent, failures }), {
		status: 200,
		headers: { 'content-type': 'application/json' }
	});
});
