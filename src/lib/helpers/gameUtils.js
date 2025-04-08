// ====================================
// 📦 GAME UTILITY FUNCTIONS
// ====================================

/**
 * Returns a formatted version of the phrase.
 * Example: breaks long phrases into multiple lines, formats case, etc.
 */
export function getFormattedPhrase(phrase, maxPerLine = 14) {
    if (!phrase) return [];
  
    const words = phrase.split(' ');
    const lines = [];
    let currentLine = '';
  
    for (let word of words) {
      if ((currentLine + word).length <= maxPerLine) {
        currentLine += (currentLine ? ' ' : '') + word;
      } else {
        lines.push(currentLine);
        currentLine = word;
      }
    }
  
    if (currentLine) {
      lines.push(currentLine);
    }
  
    return lines;
  }
  
  /**
   * Converts a 2D word/letter index (wordIndex and charIndex)
   * into the correct global index of the full phrase string.
   */
  export function getGlobalIndex(wordIndex, charIndex, phrase) {
    const words = phrase.split(' ');
    let index = 0;
  
    for (let i = 0; i < wordIndex; i++) {
      index += words[i].length + 1; // +1 for the space
    }
  
    return index + charIndex;
  }
  