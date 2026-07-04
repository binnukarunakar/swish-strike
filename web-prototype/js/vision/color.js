// vision/color.js
// ----------------------------------------------------------------------------
// Classical color-based detection — the cheap, reliable signal that beats a
// generic object model for a KNOWN-colored ball (orange basketball, etc.). Pure
// functions over an {data, width, height} image (an ImageData), so they unit-test
// in node with synthetic images. The browser feeds real downscaled frames.
// ----------------------------------------------------------------------------

/** RGB (0-255) -> HSV (h:0-360, s:0-1, v:0-1). */
export function rgbToHsv(r, g, b) {
  r /= 255; g /= 255; b /= 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min;
  let h = 0;
  if (d !== 0) {
    if (max === r) h = ((g - b) / d) % 6;
    else if (max === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    h *= 60; if (h < 0) h += 360;
  }
  return { h, s: max === 0 ? 0 : d / max, v: max };
}

function hueInRange(h, hMin, hMax) {
  return hMin <= hMax ? (h >= hMin && h <= hMax) : (h >= hMin || h <= hMax); // wraps for red
}

/** Mean luminance of a frame, 0..1 — used by the coach for a "too dark" check. */
export function brightness(img, step = 4) {
  const { data, width, height } = img;
  let sum = 0, n = 0;
  for (let y = 0; y < height; y += step) {
    for (let x = 0; x < width; x += step) {
      const i = (y * width + x) * 4;
      sum += (0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2]);
      n++;
    }
  }
  return n ? (sum / n) / 255 : 0;
}

// Named hue presets (degrees). hMin>hMax means the range wraps past 360 (red).
// 'white' is achromatic: matched by LOW saturation + HIGH value instead of hue.
export const HUES = {
  orange: { hMin: 14, hMax: 45, sMin: 0.45, vMin: 0.35 }, // basketball
  yellow: { hMin: 45, hMax: 70, sMin: 0.45, vMin: 0.45 }, // tennis
  green: { hMin: 90, hMax: 160, sMin: 0.35, vMin: 0.30 },
  blue: { hMin: 190, hMax: 240, sMin: 0.40, vMin: 0.35 },
  red: { hMin: 345, hMax: 12, sMin: 0.50, vMin: 0.35 },
  white: { sMax: 0.22, vMin: 0.78 },                      // golf/ping-pong/soccer ball
};

/**
 * Find the centroid + bbox of the largest mass of pixels matching a hue/sat/val
 * window. Returns normalized coordinates (0..1) and the matched-area fraction.
 * @param {{data:Uint8ClampedArray|number[],width:number,height:number}} img
 */
export function detectColorBlob(img, opts = {}) {
  const { hMin = 14, hMax = 45, sMin = 0.45, sMax = null, vMin = 0.35, step = 2 } = opts;
  const achromatic = sMax != null; // 'white' preset: low saturation + high value, no hue test
  const { data, width, height } = img;
  let sx = 0, sy = 0, n = 0;
  let minX = width, minY = height, maxX = 0, maxY = 0;
  for (let y = 0; y < height; y += step) {
    for (let x = 0; x < width; x += step) {
      const i = (y * width + x) * 4;
      const { h, s, v } = rgbToHsv(data[i], data[i + 1], data[i + 2]);
      const match = achromatic
        ? (s <= sMax && v >= vMin)
        : (s >= sMin && v >= vMin && hueInRange(h, hMin, hMax));
      if (match) {
        sx += x; sy += y; n++;
        if (x < minX) minX = x; if (x > maxX) maxX = x;
        if (y < minY) minY = y; if (y > maxY) maxY = y;
      }
    }
  }
  const sampled = Math.ceil(width / step) * Math.ceil(height / step);
  if (n === 0) return { found: false, x: 0, y: 0, area: 0, count: 0, bbox: null };
  return {
    found: true,
    x: (sx / n) / width,
    y: (sy / n) / height,
    area: n / sampled,
    count: n,
    bbox: { x: minX / width, y: minY / height, w: (maxX - minX) / width, h: (maxY - minY) / height },
  };
}

export default { rgbToHsv, brightness, detectColorBlob, HUES };
