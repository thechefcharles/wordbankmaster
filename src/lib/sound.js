// Lightweight WebAudio sound + haptics engine. No asset files — every cue is
// synthesised from oscillators, so there's nothing to download or bundle.
// Sound and haptics are now INDEPENDENT toggles (both persisted).
import { writable } from 'svelte/store';
import { browser } from '$app/environment';
import { Haptics, ImpactStyle, NotificationType } from '@capacitor/haptics';

const STORAGE_KEY = 'wb_sound_on';
const HAPTICS_KEY = 'wb_haptics_on';
const initial = browser ? localStorage.getItem(STORAGE_KEY) !== 'false' : true;
const initHaptics = browser ? localStorage.getItem(HAPTICS_KEY) !== 'false' : true;

/** Whether sound effects are enabled (persisted to localStorage). */
export const soundEnabled = writable(initial);
let enabled = initial;
/** @type {HTMLAudioElement | null} */ // declared here so the subscribe below can touch it
let keepAlive = null;
soundEnabled.subscribe((v) => {
	enabled = v;
	if (browser) {
		localStorage.setItem(STORAGE_KEY, String(v));
		// Hold the audio session only while sound is on (see keep-alive note below).
		if (v) playKeepAlive();
		else stopKeepAlive();
	}
});

/** Whether vibration/haptics are enabled (persisted, separate from sound). */
export const hapticsEnabled = writable(initHaptics);
let hapticsOn = initHaptics;
hapticsEnabled.subscribe((v) => {
	hapticsOn = v;
	if (browser) localStorage.setItem(HAPTICS_KEY, String(v));
});

export function toggleSound() {
	soundEnabled.update((v) => !v);
}
export function toggleHaptics() {
	hapticsEnabled.update((v) => !v);
}

/** @type {AudioContext | null} */
let ctx = null;
function ac() {
	if (!browser) return null;
	if (!ctx) {
		const AC = window.AudioContext || /** @type {any} */ (window).webkitAudioContext;
		if (!AC) return null;
		ctx = new AC();
	}
	// Browsers start the context suspended until a user gesture; resume on demand.
	if (ctx.state === 'suspended') ctx.resume().catch(() => {});
	return ctx;
}

// Silent keep-alive. On iOS/WKWebView, a Web-Audio context only produces sound while an
// <audio> element is actively playing (holding the audio session) — resuming/unlocking the
// context is NOT enough on its own. The background music used to be that element; with music
// gone, a tiny looping silence file does the same job invisibly. It plays only while sound is
// enabled (nothing to hold the session for when sound is off).
function playKeepAlive() {
	if (!browser || !enabled) return;
	if (!keepAlive) {
		keepAlive = new Audio('/silence.wav');
		keepAlive.loop = true;
		keepAlive.preload = 'auto';
	}
	keepAlive.play().catch(() => {}); // blocked until a gesture; the unlock listener retries
}
function stopKeepAlive() {
	keepAlive?.pause();
}

// iOS unlock: play a one-shot silent buffer through the context inside a real user gesture
// (resume() alone won't do it), and start the silence keep-alive. Runs on the first tap/key.
if (browser) {
	const unlock = () => {
		const c = ac();
		if (c) {
			try {
				const src = c.createBufferSource();
				src.buffer = c.createBuffer(1, 1, 22050); // one silent sample, one-shot
				src.connect(c.destination);
				src.start(0);
			} catch {
				/* try again next gesture */
			}
		}
		playKeepAlive();
		if (c && c.state === 'running' && keepAlive && !keepAlive.paused) {
			window.removeEventListener('pointerdown', unlock, true);
			window.removeEventListener('touchend', unlock, true);
			window.removeEventListener('keydown', unlock, true);
		}
	};
	window.addEventListener('pointerdown', unlock, true);
	window.addEventListener('touchend', unlock, true);
	window.addEventListener('keydown', unlock, true);
}

/**
 * A short tone with a fast attack and exponential decay.
 * @param {number} freq @param {number} dur @param {OscillatorType} [type]
 * @param {number} [gain] @param {number} [when] seconds from now
 */
function tone(freq, dur, type = 'sine', gain = 0.16, when = 0) {
	const c = ac();
	if (!c) return;
	const t0 = c.currentTime + when;
	const osc = c.createOscillator();
	const g = c.createGain();
	osc.type = type;
	osc.frequency.setValueAtTime(freq, t0);
	g.gain.setValueAtTime(0.0001, t0);
	g.gain.exponentialRampToValueAtTime(gain, t0 + 0.012);
	g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
	osc.connect(g).connect(c.destination);
	osc.start(t0);
	osc.stop(t0 + dur + 0.03);
}

/**
 * A pitch glide (whoosh-ish).
 * @param {number} f1 @param {number} f2 @param {number} dur
 * @param {OscillatorType} [type] @param {number} [gain] @param {number} [when]
 */
function sweep(f1, f2, dur, type = 'triangle', gain = 0.15, when = 0) {
	const c = ac();
	if (!c) return;
	const t0 = c.currentTime + when;
	const osc = c.createOscillator();
	const g = c.createGain();
	osc.type = type;
	osc.frequency.setValueAtTime(f1, t0);
	osc.frequency.exponentialRampToValueAtTime(Math.max(1, f2), t0 + dur);
	g.gain.setValueAtTime(0.0001, t0);
	g.gain.exponentialRampToValueAtTime(gain, t0 + 0.02);
	g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
	osc.connect(g).connect(c.destination);
	osc.start(t0);
	osc.stop(t0 + dur + 0.03);
}

/** @type {Record<string, () => void>} */
const SOUNDS = {
	tap: () => tone(420, 0.05, 'square', 0.05),
	select: () => tone(660, 0.07, 'sine', 0.09),
	correct: () => {
		tone(720, 0.1, 'sine', 0.15);
		tone(960, 0.12, 'sine', 0.11, 0.06);
	},
	wrong: () => tone(150, 0.2, 'sawtooth', 0.11),
	reveal: () => sweep(420, 1150, 0.24, 'triangle', 0.13),
	// Box landing thunk for the daily opening reveal: a low knock + a bright coin ping.
	land: () => {
		tone(180, 0.08, 'square', 0.13);
		tone(1180, 0.09, 'sine', 0.09, 0.03);
	},
	win: () => [523, 659, 784, 1047].forEach((f, i) => tone(f, 0.2, 'sine', 0.16, i * 0.09)),
	bust: () => sweep(440, 80, 0.55, 'sawtooth', 0.16),
	multiplier: () => {
		tone(880, 0.09, 'sine', 0.13);
		tone(1320, 0.13, 'sine', 0.12, 0.08);
	},
	// Bright rising blip — you just took the lead in a challenge.
	lead: () => {
		tone(784, 0.08, 'sine', 0.12);
		tone(1175, 0.12, 'sine', 0.11, 0.07);
	},
	// Heavy metallic vault CLUNK: mechanism click → deep thunk → metal overtone.
	vault: () => {
		tone(140, 0.05, 'square', 0.16); // latch click
		tone(82, 0.34, 'sine', 0.34, 0.03); // heavy thunk
		tone(58, 0.42, 'triangle', 0.24, 0.05); // low body
		tone(360, 0.2, 'triangle', 0.07, 0.04); // metallic ring
		sweep(520, 180, 0.3, 'sawtooth', 0.06, 0.05); // dampened resonance
	},
	// 🧾 Thermal-receipt printer: a buzzy stepper-motor ratchet that feeds for ~2.8s while
	// the slip prints, then a soft cut. Built from a bandpassed sawtooth gated by a fast
	// square LFO (the "brrrt"), with a gentle overall fade in/out.
	print: () => {
		const c = ac();
		if (!c) return;
		const t0 = c.currentTime;
		const dur = 2.8;
		const out = c.createGain();
		out.gain.value = 0.6;
		out.connect(c.destination);
		// Motor whine carrier, drifting slightly down as the roll spins out.
		const osc = c.createOscillator();
		osc.type = 'sawtooth';
		osc.frequency.setValueAtTime(152, t0);
		osc.frequency.linearRampToValueAtTime(136, t0 + dur);
		// Bandpass → mechanical buzz rather than a raw saw.
		const bp = c.createBiquadFilter();
		bp.type = 'bandpass';
		bp.frequency.value = 880;
		bp.Q.value = 3.2;
		// Ratchet: a square LFO gates amplitude on/off (~46 steps/sec) → the "brrr".
		const gate = c.createGain();
		gate.gain.value = 0.5;
		const lfo = c.createOscillator();
		lfo.type = 'square';
		lfo.frequency.value = 46;
		const lfoAmt = c.createGain();
		lfoAmt.gain.value = 0.45;
		lfo.connect(lfoAmt).connect(gate.gain);
		// Overall envelope.
		const env = c.createGain();
		env.gain.setValueAtTime(0, t0);
		env.gain.linearRampToValueAtTime(0.055, t0 + 0.08);
		env.gain.setValueAtTime(0.055, t0 + dur - 0.18);
		env.gain.linearRampToValueAtTime(0, t0 + dur);
		osc.connect(bp).connect(gate).connect(env).connect(out);
		osc.start(t0);
		lfo.start(t0);
		osc.stop(t0 + dur + 0.05);
		lfo.stop(t0 + dur + 0.05);
	}
};

/** @type {Record<string, number[]>} */
const HAPTICS = {
	tap: [8],
	select: [8],
	correct: [14],
	wrong: [22, 36, 22],
	reveal: [12],
	land: [10],
	win: [18, 40, 18, 40, 36],
	bust: [60, 30, 60],
	multiplier: [10, 24, 10],
	lead: [12, 20, 16],
	vault: [50, 30, 90],
	// Light stutter that rides along with the ~2.8s print buzz.
	print: [14, 60, 14, 60, 14, 60, 14, 60, 14, 60, 14, 60, 14]
};

/** Play an audio cue by name (no-op when disabled). @param {string} name */
export function playSound(name) {
	if (!enabled) return;
	const fn = SOUNDS[name];
	if (fn) {
		try {
			fn();
		} catch {
			/* audio is best-effort */
		}
	}
}

// Map each cue to a Capacitor Haptics call (real haptics on iOS; falls back to
// navigator.vibrate on web). Tunes intensity per event.
/** @param {string} name @returns {Promise<any>} */
function nativeHaptic(name) {
	switch (name) {
		case 'win':
			return Haptics.notification({ type: NotificationType.Success });
		case 'wrong':
			return Haptics.notification({ type: NotificationType.Warning });
		case 'bust':
			return Haptics.notification({ type: NotificationType.Error });
		case 'vault':
			return Haptics.impact({ style: ImpactStyle.Heavy });
		case 'multiplier':
		case 'lead':
			return Haptics.impact({ style: ImpactStyle.Medium });
		default:
			return Haptics.impact({ style: ImpactStyle.Light });
	}
}

/** Fire a haptic by name (no-op when haptics are off / unsupported). @param {string} name */
export function vibrate(name) {
	if (!hapticsOn || !browser) return;
	if (!(name in HAPTICS)) return;
	try {
		nativeHaptic(name).catch(() => {
			// last-resort web fallback if the plugin couldn't run
			if (navigator.vibrate) navigator.vibrate(HAPTICS[name]);
		});
	} catch {
		if (navigator.vibrate)
			try {
				navigator.vibrate(HAPTICS[name]);
			} catch {
				/* best-effort */
			}
	}
}

/** @type {Record<string, number>} */
const _lastFx = {};
/** Combined sound + haptic feedback for a named event. @param {string} name */
export function fx(name) {
	// Collapse rapid duplicate cues (e.g. the global button beep + a handler's own fx('tap')).
	if (browser) {
		const now = typeof performance !== 'undefined' ? performance.now() : 0;
		if (_lastFx[name] && now - _lastFx[name] < 60) return;
		_lastFx[name] = now;
	}
	playSound(name);
	vibrate(name);
}
