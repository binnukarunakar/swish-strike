// cv.test.mjs — unit tests for the classical CV primitives (HSV color-blob +
// frame-difference motion) against synthetic images. Run: node --test
// These verify the "better detection" signals headlessly, without a camera.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { rgbToHsv, brightness, detectColorBlob, HUES } from '../js/vision/color.js';
import { motionCentroid } from '../js/vision/motion.js';

function makeImage(w, h, fill = [10, 10, 12]) {
  const data = new Uint8ClampedArray(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    data[i * 4] = fill[0]; data[i * 4 + 1] = fill[1]; data[i * 4 + 2] = fill[2]; data[i * 4 + 3] = 255;
  }
  return { data, width: w, height: h };
}
function fillRect(img, x0, y0, w, h, c) {
  for (let y = y0; y < y0 + h; y++) {
    for (let x = x0; x < x0 + w; x++) {
      const i = (y * img.width + x) * 4;
      img.data[i] = c[0]; img.data[i + 1] = c[1]; img.data[i + 2] = c[2];
    }
  }
}

test('rgbToHsv: orange maps to ~33° hue, full sat/val', () => {
  const { h, s, v } = rgbToHsv(255, 140, 0);
  assert.ok(h > 25 && h < 40, `hue ${h}`);
  assert.ok(s > 0.9 && v > 0.9);
});

test('detectColorBlob: finds an orange ball centroid + area', () => {
  const img = makeImage(100, 100);
  fillRect(img, 40, 40, 20, 20, [255, 140, 0]); // orange square, centered
  const r = detectColorBlob(img); // default orange window
  assert.ok(r.found);
  assert.ok(Math.abs(r.x - 0.5) < 0.05 && Math.abs(r.y - 0.5) < 0.05, `centroid ${r.x},${r.y}`);
  assert.ok(r.area > 0.02 && r.area < 0.08, `area ${r.area}`);
});

test('detectColorBlob: no false positive on a colorless frame', () => {
  const img = makeImage(100, 100, [30, 30, 30]); // gray, no saturated hue
  assert.equal(detectColorBlob(img).found, false);
});

test('detectColorBlob: white preset finds a white ball on a dark frame, ignores gray', () => {
  const img = makeImage(100, 100, [60, 60, 60]); // mid-gray bg (v too low for white)
  fillRect(img, 45, 45, 12, 12, [245, 245, 245]); // white golf ball
  const r = detectColorBlob(img, HUES.white);
  assert.ok(r.found);
  assert.ok(Math.abs(r.x - 0.5) < 0.06 && Math.abs(r.y - 0.5) < 0.06, `centroid ${r.x},${r.y}`);
  // and an orange ball does NOT match the white preset
  const img2 = makeImage(100, 100, [10, 10, 12]);
  fillRect(img2, 45, 45, 12, 12, [255, 140, 0]);
  assert.equal(detectColorBlob(img2, HUES.white).found, false);
});

test('brightness: dark vs bright frames separate cleanly', () => {
  assert.ok(brightness(makeImage(60, 60, [10, 10, 12])) < 0.12);
  assert.ok(brightness(makeImage(60, 60, [200, 200, 200])) > 0.6);
});

test('motionCentroid: identical frames -> no motion', () => {
  const a = makeImage(100, 100);
  const b = makeImage(100, 100);
  assert.equal(motionCentroid(a, b).found, false);
});

test('motionCentroid: a moved bright object is localized', () => {
  const prev = makeImage(100, 100);
  const cur = makeImage(100, 100);
  fillRect(cur, 55, 40, 10, 10, [220, 220, 220]); // appears at ~ (60,45)
  const r = motionCentroid(prev, cur);
  assert.ok(r.found);
  assert.ok(Math.abs(r.x - 0.60) < 0.06 && Math.abs(r.y - 0.45) < 0.06, `centroid ${r.x},${r.y}`);
});
