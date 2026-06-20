// Build the transparent brand PNGs in static/ from the sources in brand/.
//  - 'white' / 'black': knock a solid background out to alpha (soft edges).
//  - 'keep': source already has alpha; just auto-trim the transparent margins.
// No native deps (jpeg-js + pngjs are pure JS).
const fs = require('fs');
const jpeg = require('jpeg-js');
const { PNG } = require('pngjs');

const clamp = (v) => Math.max(0, Math.min(255, Math.round(v)));

function decode(src) {
  const buf = fs.readFileSync(src);
  if (src.endsWith('.png')) {
    const p = PNG.sync.read(buf);
    return { width: p.width, height: p.height, data: p.data };
  }
  const j = jpeg.decode(buf, { maxMemoryUsageInMB: 512 });
  return { width: j.width, height: j.height, data: j.data };
}

/**
 * @param {string} src @param {string} dst @param {'white'|'black'|'keep'} bg
 */
function build(src, dst, bg) {
  const { width, height, data } = decode(src);
  const alpha = new Uint8Array(width * height);
  let minX = width, minY = height, maxX = -1, maxY = -1;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const i = y * width + x;
      const r = data[i * 4], g = data[i * 4 + 1], b = data[i * 4 + 2];
      let a;
      if (bg === 'white') a = clamp((255 - Math.min(r, g, b) - 20) * 16);
      else if (bg === 'black') a = clamp((Math.max(r, g, b) - 12) * 3);
      else a = data[i * 4 + 3]; // keep existing alpha
      alpha[i] = a;
      if (a > 24) {
        if (x < minX) minX = x; if (x > maxX) maxX = x;
        if (y < minY) minY = y; if (y > maxY) maxY = y;
      }
    }
  }
  const pad = Math.round(Math.max(width, height) * 0.02);
  minX = Math.max(0, minX - pad); minY = Math.max(0, minY - pad);
  maxX = Math.min(width - 1, maxX + pad); maxY = Math.min(height - 1, maxY + pad);
  const w = maxX - minX + 1, h = maxY - minY + 1;
  const out = new PNG({ width: w, height: h });
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const si = ((y + minY) * width + (x + minX)) * 4;
      const di = (y * w + x) * 4;
      out.data[di] = data[si];
      out.data[di + 1] = data[si + 1];
      out.data[di + 2] = data[si + 2];
      out.data[di + 3] = alpha[(y + minY) * width + (x + minX)];
    }
  }
  fs.writeFileSync(dst, PNG.sync.write(out));
  console.log(`wrote ${dst} (${w}x${h}, from ${width}x${height})`);
}

// Coin mark — lossless PNG source, knock out the white backing.
build('brand/letter-mark.src.png', 'static/logo-mark.png', 'white');
// Hero lockup — already transparent, just trim the margins.
build('brand/wordmark-slogan.src.png', 'static/wordmark-slogan.png', 'keep');
// Compact wordmark (no slogan) for the in-game header.
build('brand/wordmark.src.jpg', 'static/wordmark.png', 'black');
