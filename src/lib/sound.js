// Lightweight WebAudio sound + haptics engine. No asset files — every cue is
// synthesised from oscillators, so there's nothing to download or bundle.
// One toggle (persisted) controls both audio and vibration ("feedback").
import { writable } from 'svelte/store';
import { browser } from '$app/environment';

const STORAGE_KEY = 'wb_sound_on';
const initial = browser ? localStorage.getItem(STORAGE_KEY) !== 'false' : true;

/** Whether sound + haptics are enabled (persisted to localStorage). */
export const soundEnabled = writable(initial);
let enabled = initial;
soundEnabled.subscribe((v) => {
  enabled = v;
  if (browser) localStorage.setItem(STORAGE_KEY, String(v));
});

export function toggleSound() {
  soundEnabled.update((v) => !v);
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
  win: () => [523, 659, 784, 1047].forEach((f, i) => tone(f, 0.2, 'sine', 0.16, i * 0.09)),
  bust: () => sweep(440, 80, 0.55, 'sawtooth', 0.16),
  multiplier: () => {
    tone(880, 0.09, 'sine', 0.13);
    tone(1320, 0.13, 'sine', 0.12, 0.08);
  }
};

/** @type {Record<string, number[]>} */
const HAPTICS = {
  tap: [8],
  select: [8],
  correct: [14],
  wrong: [22, 36, 22],
  reveal: [12],
  win: [18, 40, 18, 40, 36],
  bust: [60, 30, 60],
  multiplier: [10, 24, 10]
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

/** Fire a haptic pattern by name (no-op when disabled / unsupported). @param {string} name */
export function vibrate(name) {
  if (!enabled || !browser || !navigator.vibrate) return;
  const p = HAPTICS[name];
  if (p) {
    try {
      navigator.vibrate(p);
    } catch {
      /* haptics are best-effort */
    }
  }
}

/** Combined sound + haptic feedback for a named event. @param {string} name */
export function fx(name) {
  playSound(name);
  vibrate(name);
}
