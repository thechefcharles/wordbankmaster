// Build opaque, square iOS icon + splash sources from the brand coin logo.
// iOS app icons may NOT have an alpha channel, so we composite the (transparent)
// logo over the app's dark background and flatten. Output feeds @capacitor/assets.
const { PNG } = require('pngjs');
const fs = require('fs');

const SRC = 'static/logo-mark.png';
const BG = [10, 14, 20]; // #0a0e14 — matches the app background
const src = PNG.sync.read(fs.readFileSync(SRC));

/** Render the logo centered on a SIZE×SIZE opaque dark canvas, logo at `pad` of the canvas. */
function compose(size, pad) {
  const out = new PNG({ width: size, height: size });
  for (let i = 0; i < out.data.length; i += 4) {
    out.data[i] = BG[0]; out.data[i + 1] = BG[1]; out.data[i + 2] = BG[2]; out.data[i + 3] = 255;
  }
  const maxDim = size * pad;
  const scale = Math.min(maxDim / src.width, maxDim / src.height);
  const w = Math.round(src.width * scale);
  const h = Math.round(src.height * scale);
  const ox = Math.round((size - w) / 2);
  const oy = Math.round((size - h) / 2);
  // Area-average downscale (premultiplied) for a clean, non-aliased logo.
  for (let y = 0; y < h; y++) {
    const sy0 = Math.floor(y / scale), sy1 = Math.min(src.height, Math.floor((y + 1) / scale) + 1);
    for (let x = 0; x < w; x++) {
      const sx0 = Math.floor(x / scale), sx1 = Math.min(src.width, Math.floor((x + 1) / scale) + 1);
      let r = 0, g = 0, b = 0, a = 0, n = 0;
      for (let sy = sy0; sy < sy1; sy++) {
        for (let sx = sx0; sx < sx1; sx++) {
          const si = (sy * src.width + sx) * 4;
          const al = src.data[si + 3] / 255;
          r += src.data[si] * al; g += src.data[si + 1] * al; b += src.data[si + 2] * al;
          a += al; n++;
        }
      }
      if (n === 0) continue;
      const af = a / n;                         // mean coverage
      const dr = af > 0 ? r / a : 0, dg = af > 0 ? g / a : 0, db = af > 0 ? b / a : 0;
      const di = ((oy + y) * size + (ox + x)) * 4;
      out.data[di]     = Math.round(dr * af + BG[0] * (1 - af));
      out.data[di + 1] = Math.round(dg * af + BG[1] * (1 - af));
      out.data[di + 2] = Math.round(db * af + BG[2] * (1 - af));
      out.data[di + 3] = 255;
    }
  }
  return PNG.sync.write(out);
}

fs.mkdirSync('assets', { recursive: true });
fs.writeFileSync('assets/icon.png', compose(1024, 0.72));            // app icon
const splash = compose(2732, 0.30);                                  // launch screen
fs.writeFileSync('assets/splash.png', splash);
fs.writeFileSync('assets/splash-dark.png', splash);
console.log('wrote assets/icon.png (1024), assets/splash.png + splash-dark.png (2732)');
