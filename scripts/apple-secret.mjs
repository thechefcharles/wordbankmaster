// Generates the Apple "Sign in with Apple" client secret JWT for Supabase.
// (This is the "Secret Key (for OAuth)" field — it's a signed ES256 JWT, NOT the
//  raw .p8. Apple makes it expire every 6 months, so re-run this to refresh it.)
//
// Usage:
//   TEAM_ID=ABCDE12345 \
//   KEY_ID=XYZ1234567 \
//   CLIENT_ID=app.wordbank.signin \
//   KEY_PATH=./AuthKey_XYZ1234567.p8 \
//   node scripts/apple-secret.mjs
//
//   TEAM_ID   = your Apple Team ID (top-right of developer.apple.com)
//   KEY_ID    = the Key ID of the "Sign in with Apple" key you created
//   CLIENT_ID = your Services ID (the same value you put in Supabase "Client IDs")
//   KEY_PATH  = path to the AuthKey_*.p8 you downloaded from Apple

import crypto from 'node:crypto';
import fs from 'node:fs';

const { TEAM_ID, KEY_ID, CLIENT_ID, KEY_PATH } = process.env;
if (!TEAM_ID || !KEY_ID || !CLIENT_ID || !KEY_PATH) {
	console.error(
		'Missing env. Need TEAM_ID, KEY_ID, CLIENT_ID, KEY_PATH. See the header of this file.'
	);
	process.exit(1);
}

const b64url = (buf) => Buffer.from(buf).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const header = { alg: 'ES256', kid: KEY_ID };
const payload = {
	iss: TEAM_ID,
	iat: now,
	exp: now + 60 * 60 * 24 * 180, // ~6 months (Apple's max)
	aud: 'https://appleid.apple.com',
	sub: CLIENT_ID
};

const signingInput = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;
const key = crypto.createPrivateKey(fs.readFileSync(KEY_PATH));
const sig = crypto.sign('sha256', Buffer.from(signingInput), { key, dsaEncoding: 'ieee-p1363' });

console.log(`${signingInput}.${b64url(sig)}`);
console.error(
	'\n↑ Paste this into Supabase → Auth → Providers → Apple → "Secret Key (for OAuth)". Expires in ~6 months.'
);
