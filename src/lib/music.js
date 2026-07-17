// Looping background music. A single module-level <audio> element (a singleton, so
// it survives route changes) plays continuously the whole session — menu AND during
// gameplay/puzzles — so it never stutters when screens change or sfx fire. Volume +
// on/off + the chosen track persist to localStorage. To add a beat: drop the file in
// static/music/ and add an entry to TRACKS — the picker + switching come for free.
import { writable } from 'svelte/store';
import { browser } from '$app/environment';

/** Track manifest. id is stable + persisted; src is under static/. The UI labels them
 *  "Track 1/2/3" by position, so the order here is what the player sees. */
export const TRACKS = [
	{ id: 'native-jazz', title: 'Native Jazz', src: '/music/native-jazz.mp3' },
	{ id: 'young-love', title: 'Young Love', src: '/music/young-love.mp3' },
	{ id: 'stu-ball-recipes', title: 'Stu Ball Recipes', src: '/music/stu-ball-recipes.mp3' }
];

// VOL_KEY bumped to _v2 so the lower default takes effect for everyone (old saved
// volumes are ignored). Menu-only music + this quieter default = a soft background bed.
const VOL_KEY = 'wb_music_vol_v2';
const ON_KEY = 'wb_music_on';
const TRACK_KEY = 'wb_music_track';
const DEFAULT_VOL = 0.08; // soft background (~8%) — menu-only, shouldn't dominate

/** @param {any} v @param {number} d */
function clamp01(v, d) {
	if (v === null || v === undefined || v === '') return d; // unset → default (Number(null) is 0, not NaN!)
	const n = Number(v);
	return Number.isFinite(n) ? Math.min(1, Math.max(0, n)) : d;
}

const initVol = browser ? clamp01(localStorage.getItem(VOL_KEY), DEFAULT_VOL) : DEFAULT_VOL;
const initOn = browser ? localStorage.getItem(ON_KEY) !== 'false' : true;
const initTrack = browser ? localStorage.getItem(TRACK_KEY) || TRACKS[0].id : TRACKS[0].id;

/** Whether lobby music is enabled (persisted). */
export const musicEnabled = writable(initOn);
/** Music volume 0..1 (persisted). */
export const musicVolume = writable(initVol);
/** Currently selected track id (persisted). */
export const currentTrackId = writable(initTrack);

let enabled = initOn;
let volume = initVol;
let trackId = initTrack;
let wantPlaying = false; // the lobby wants music on
let armed = false;
/** @type {HTMLAudioElement|null} */
let audio = null;

/** @param {string} id */
function trackById(id) {
	return TRACKS.find((t) => t.id === id) || TRACKS[0];
}

function ensureAudio() {
	if (!browser) return null;
	if (!audio) {
		audio = new Audio(trackById(trackId).src);
		audio.loop = true;
		audio.preload = 'auto';
		audio.volume = enabled ? volume : 0;
	}
	return audio;
}

function apply() {
	const a = audio;
	if (!a) return;
	a.volume = enabled ? volume : 0;
	if (wantPlaying && enabled) a.play().catch(() => armAutoplay());
	else if (!enabled) a.pause();
}

// Browsers block audio until a user gesture. If play() is rejected, wait for the
// next tap/keypress and try again, then stop listening.
function armAutoplay() {
	if (!browser || armed) return;
	armed = true;
	const onGesture = () => {
		if (wantPlaying && enabled && audio) {
			audio
				.play()
				.then(cleanup)
				.catch(() => {});
		} else {
			cleanup();
		}
	};
	function cleanup() {
		window.removeEventListener('pointerdown', onGesture);
		window.removeEventListener('keydown', onGesture);
		armed = false;
	}
	window.addEventListener('pointerdown', onGesture);
	window.addEventListener('keydown', onGesture);
}

musicEnabled.subscribe((v) => {
	enabled = v;
	if (browser) localStorage.setItem(ON_KEY, String(v));
	apply();
});
musicVolume.subscribe((v) => {
	volume = clamp01(v, DEFAULT_VOL);
	if (browser) localStorage.setItem(VOL_KEY, String(volume));
	if (audio) audio.volume = enabled ? volume : 0;
});
currentTrackId.subscribe((v) => {
	if (!v) return;
	const changed = v !== trackId;
	trackId = v;
	if (browser) localStorage.setItem(TRACK_KEY, v);
	if (changed && audio) {
		audio.src = trackById(trackId).src;
		audio.load();
		if (wantPlaying && enabled) audio.play().catch(() => armAutoplay());
	}
});

/** Start lobby music (call when entering the menu lobby). */
export function startMusic() {
	wantPlaying = true;
	const a = ensureAudio();
	if (!a) return;
	if (enabled) a.play().catch(() => armAutoplay());
}

/** Pause lobby music (call when leaving the lobby / starting a game). */
export function stopMusic() {
	wantPlaying = false;
	if (audio) audio.pause();
}

/** @param {number} v 0..1 */
export function setMusicVolume(v) {
	musicVolume.set(clamp01(v, DEFAULT_VOL));
}
export function toggleMusic() {
	musicEnabled.update((v) => !v);
}
/** @param {string} id */
export function selectTrack(id) {
	currentTrackId.set(id);
}
