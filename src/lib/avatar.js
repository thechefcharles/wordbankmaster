// Avatar model — DiceBear "avataaars" dress-up. The customizer options below are
// the single source of truth; paid options carry a cosmeticId + price that match
// the `cosmetics` catalog rows (see supabase-avatars.sql). Free options have no price.
import { createAvatar } from '@dicebear/core';
import { avataaars } from '@dicebear/collection';

/** A sensible starter look for brand-new players. */
export const DEFAULT_AVATAR = {
  skinColor: 'edb98a', top: 'shortFlat', hairColor: '4a312c',
  eyes: 'default', eyebrows: 'default', mouth: 'smile',
  clothing: 'shirtCrewNeck', clothesColor: '5199e4',
  accessories: 'none', facialHair: 'none'
};

const SKIN = ['ffdbb4', 'edb98a', 'fd9841', 'f8d25c', 'd08b5b', 'ae5d29', '614335'];
const HAIR = ['2c1b18', '4a312c', '724133', 'a55728', 'b58143', 'c93305', 'd6b370', 'e8e1e1', 'ecdcbf', 'f59797'];
const OUTFIT = ['262e33', '3c4f5c', '5199e4', '25557c', '65c9ff', '929598', 'a7ffc4', 'ff488e', 'ff5c5c', 'ffffb1', 'ffffff'];
const col = (/** @type {string[]} */ a) => a.map((value) => ({ value, label: '#' + value }));

/** Ordered builder categories. `type:'color'` = swatches, `type:'style'` = thumbnails.
 *  Options with a `price` are paid (must be owned to equip). @type {any[]} */
export const CATEGORIES = [
  { key: 'skinColor', label: 'Skin', type: 'color', options: col(SKIN) },
  { key: 'top', label: 'Hair & Hats', type: 'style', options: [
    { value: 'none', label: 'Bald' }, { value: 'shortFlat', label: 'Short' }, { value: 'shortRound', label: 'Buzz' },
    { value: 'shortWaved', label: 'Waved' }, { value: 'straight01', label: 'Straight' }, { value: 'bun', label: 'Bun' },
    { value: 'shavedSides', label: 'Shaved Sides' }, { value: 'longButNotTooLong', label: 'Long' }, { value: 'sides', label: 'Sides' },
    { value: 'theCaesar', label: 'Caesar' }, { value: 'hijab', label: 'Hijab' }, { value: 'turban', label: 'Turban' },
    { value: 'curly', label: 'Curly', cosmeticId: 'av_top_curly', price: 300 },
    { value: 'miaWallace', label: 'Long Bob', cosmeticId: 'av_top_miawallace', price: 400 },
    { value: 'fro', label: 'Afro', cosmeticId: 'av_top_fro', price: 400 },
    { value: 'dreads', label: 'Dreads', cosmeticId: 'av_top_dreads', price: 500 },
    { value: 'bigHair', label: 'Big Hair', cosmeticId: 'av_top_bighair', price: 500 },
    { value: 'frida', label: 'Frida', cosmeticId: 'av_top_frida', price: 600 },
    { value: 'hat', label: 'Fedora', cosmeticId: 'av_top_hat', price: 600 },
    { value: 'winterHat1', label: 'Beanie', cosmeticId: 'av_top_beanie', price: 400 },
    { value: 'winterHat03', label: 'Bobble Hat', cosmeticId: 'av_top_bobble', price: 500 }
  ] },
  { key: 'hairColor', label: 'Hair Color', type: 'color', options: col(HAIR) },
  { key: 'eyes', label: 'Eyes', type: 'style', options: [
    { value: 'default', label: 'Default' }, { value: 'happy', label: 'Happy' }, { value: 'wink', label: 'Wink' },
    { value: 'squint', label: 'Squint' }, { value: 'side', label: 'Side' }, { value: 'surprised', label: 'Surprised' }, { value: 'hearts', label: 'Hearts' }
  ] },
  { key: 'eyebrows', label: 'Brows', type: 'style', options: [
    { value: 'default', label: 'Default' }, { value: 'defaultNatural', label: 'Natural' }, { value: 'raisedExcited', label: 'Raised' },
    { value: 'flatNatural', label: 'Flat' }, { value: 'sadConcerned', label: 'Sad' }, { value: 'angry', label: 'Angry' }
  ] },
  { key: 'mouth', label: 'Mouth', type: 'style', options: [
    { value: 'smile', label: 'Smile' }, { value: 'default', label: 'Default' }, { value: 'twinkle', label: 'Twinkle' },
    { value: 'serious', label: 'Serious' }, { value: 'eating', label: 'Eating' }, { value: 'tongue', label: 'Tongue' }
  ] },
  { key: 'facialHair', label: 'Beard', type: 'style', options: [
    { value: 'none', label: 'None' },
    { value: 'beardLight', label: 'Light Beard', cosmeticId: 'av_beard_light', price: 300 },
    { value: 'beardMedium', label: 'Beard', cosmeticId: 'av_beard_medium', price: 400 },
    { value: 'beardMajestic', label: 'Majestic', cosmeticId: 'av_beard_majestic', price: 700 },
    { value: 'moustacheFancy', label: 'Fancy Stache', cosmeticId: 'av_must_fancy', price: 400 },
    { value: 'moustacheMagnum', label: 'Magnum Stache', cosmeticId: 'av_must_magnum', price: 400 }
  ] },
  { key: 'clothing', label: 'Clothes', type: 'style', options: [
    { value: 'shirtCrewNeck', label: 'Crew Tee' }, { value: 'shirtVNeck', label: 'V-Neck' }, { value: 'shirtScoopNeck', label: 'Scoop Tee' },
    { value: 'hoodie', label: 'Hoodie', cosmeticId: 'av_cloth_hoodie', price: 400 },
    { value: 'graphicShirt', label: 'Graphic Tee', cosmeticId: 'av_cloth_graphic', price: 300 },
    { value: 'collarAndSweater', label: 'Collar & Sweater', cosmeticId: 'av_cloth_collar', price: 600 },
    { value: 'overall', label: 'Overalls', cosmeticId: 'av_cloth_overall', price: 500 },
    { value: 'blazerAndShirt', label: 'Blazer', cosmeticId: 'av_cloth_blazer', price: 800 },
    { value: 'blazerAndSweater', label: 'Blazer & Sweater', cosmeticId: 'av_cloth_blazersw', price: 900 }
  ] },
  { key: 'clothesColor', label: 'Outfit Color', type: 'color', options: col(OUTFIT) },
  { key: 'accessories', label: 'Glasses', type: 'style', options: [
    { value: 'none', label: 'None' },
    { value: 'round', label: 'Round', cosmeticId: 'av_acc_round', price: 300 },
    { value: 'sunglasses', label: 'Sunglasses', cosmeticId: 'av_acc_sunglasses', price: 500 },
    { value: 'wayfarers', label: 'Wayfarers', cosmeticId: 'av_acc_wayfarers', price: 500 },
    { value: 'prescription01', label: 'Specs', cosmeticId: 'av_acc_specs', price: 300 },
    { value: 'kurt', label: 'Kurt', cosmeticId: 'av_acc_kurt', price: 400 },
    { value: 'eyepatch', label: 'Eyepatch', cosmeticId: 'av_acc_eyepatch', price: 700 }
  ] }
];

/** Map an avatar config to DiceBear avataaars options (forcing single values). @param {any} config */
export function avataaarsOptions(config) {
  const c = { ...DEFAULT_AVATAR, ...(config || {}) };
  return {
    seed: 'wb',
    backgroundColor: ['transparent'],
    skinColor: [c.skinColor],
    top: c.top === 'none' ? [] : [c.top],
    topProbability: c.top === 'none' ? 0 : 100,
    hairColor: [c.hairColor],
    hatColor: [c.clothesColor],
    eyes: [c.eyes],
    eyebrows: [c.eyebrows],
    mouth: [c.mouth],
    facialHair: c.facialHair === 'none' ? [] : [c.facialHair],
    facialHairProbability: c.facialHair === 'none' ? 0 : 100,
    clothing: [c.clothing],
    clothesColor: [c.clothesColor],
    accessories: c.accessories === 'none' ? [] : [c.accessories],
    accessoriesProbability: c.accessories === 'none' ? 0 : 100
  };
}

/** Render an avatar config to an SVG string. @param {any} config @param {any} [extra] extra DiceBear opts */
export function renderAvatarSvg(config, extra = {}) {
  return createAvatar(avataaars, { ...avataaarsOptions(config), ...extra }).toString();
}

/** PREMIUM FX: render the avatar with an animated holographic/iridescent shirt.
 *  Works by rendering the clothing in a sentinel colour, then swapping that fill
 *  for an animated multi-stop gradient. @param {any} config */
export function renderHoloAvatar(config) {
  const SENTINEL = '00fe01'; // an unlikely colour we can find + replace
  let svg = renderAvatarSvg({ ...config, clothesColor: SENTINEL });
  const defs =
    '<defs><linearGradient id="wbHolo" gradientUnits="userSpaceOnUse" x1="40" y1="195" x2="240" y2="285" spreadMethod="reflect">' +
    '<stop offset="0" stop-color="#ff5cf0"/><stop offset="0.3" stop-color="#5cd0ff"/>' +
    '<stop offset="0.6" stop-color="#7cff6b"/><stop offset="1" stop-color="#ffe45c"/>' +
    '<animateTransform attributeName="gradientTransform" type="translate" values="0 0;130 65;0 0" dur="3s" repeatCount="indefinite"/>' +
    '</linearGradient></defs>';
  svg = svg.replace('>', '>' + defs);
  return svg.replace(new RegExp('#' + SENTINEL, 'gi'), 'url(#wbHolo)');
}
