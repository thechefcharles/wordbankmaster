// The 12 puzzle categories. `value` is the exact string stored on
// daily_puzzles.category (emoji included) and passed to freeplay_start.
/** @type {{ value: string, label: string, emoji: string }[]} */
export const CATEGORIES = [
  { value: 'Movies & TV 🎬',        label: 'Movies & TV',       emoji: '🎬' },
  { value: 'Music 🎵',             label: 'Music',             emoji: '🎵' },
  { value: 'Famous People 🌟',     label: 'Famous People',     emoji: '🌟' },
  { value: 'Food & Drink 🍔',      label: 'Food & Drink',      emoji: '🍔' },
  { value: 'Places & Travel ✈️',   label: 'Places & Travel',   emoji: '✈️' },
  { value: 'Sports 🏆',            label: 'Sports',            emoji: '🏆' },
  { value: 'Phrases & Sayings 🗣️', label: 'Phrases & Sayings', emoji: '🗣️' },
  { value: 'Science & Nature 🔬',  label: 'Science & Nature',  emoji: '🔬' },
  { value: 'Books & Characters 📚', label: 'Books & Characters', emoji: '📚' },
  { value: 'Video Games 🎮',       label: 'Video Games',       emoji: '🎮' },
  { value: 'Brands & Logos 🏷️',    label: 'Brands & Logos',    emoji: '🏷️' },
  { value: 'Tech & Internet 💻',   label: 'Tech & Internet',   emoji: '💻' }
];
