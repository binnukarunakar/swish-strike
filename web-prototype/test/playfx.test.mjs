// playfx.test.mjs — the play-phase effects (comet trail + heat meter) are pure
// data structures, so they're tested directly without a browser.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { TrailBuffer, Heat } from '../js/playfx.js';

test('TrailBuffer keeps only points inside the fade window, freshest fade highest', () => {
  const tb = new TrailBuffer({ maxAgeMs: 800, max: 64 });
  tb.push(0, 0.5, 0.5);     // age 800ms at now=800 → exactly on the edge
  tb.push(400, 0.5, 0.4);
  tb.push(800, 0.5, 0.3);   // freshest
  const live = tb.live(800);
  assert.equal(live.length, 3);
  assert.ok(live[2].fade > live[0].fade, 'newer points fade in stronger');
  assert.ok(live[2].fade > 0.99, 'the just-pushed point is fully opaque');
});

test('TrailBuffer drops points older than the window', () => {
  const tb = new TrailBuffer({ maxAgeMs: 500 });
  tb.push(0, 0.5, 0.5);
  tb.push(1000, 0.5, 0.5);
  assert.equal(tb.live(1000).length, 1, 'the 1000ms-old point has expired');
});

test('TrailBuffer ignores non-finite coordinates (engine misses)', () => {
  const tb = new TrailBuffer();
  tb.push(0, NaN, 0.5);
  tb.push(10, 0.5, undefined);
  assert.equal(tb.pts.length, 0);
});

test('TrailBuffer.snapshotArc returns the recent arc as plain points', () => {
  const tb = new TrailBuffer();
  tb.push(0, 0.5, 0.9);
  tb.push(100, 0.5, 0.5);
  tb.push(200, 0.5, 0.2);
  const arc = tb.snapshotArc(200, 1400);
  assert.deepEqual(arc, [{ x: 0.5, y: 0.9 }, { x: 0.5, y: 0.5 }, { x: 0.5, y: 0.2 }]);
});

test('Heat rises on score, caps at 1 for rendering, and reports on-fire', () => {
  const h = new Heat({ perScore: 0.34, decayPerSec: 0.5 });
  h.tick(0);
  h.bump(); h.bump(); h.bump();          // ~1.02 internal
  assert.equal(h.tick(0), 1, 'level is clamped to 1');
  assert.ok(h.onFire, 'three quick scores light the fire');
});

test('Heat decays toward zero over time', () => {
  const h = new Heat({ perScore: 0.34, decayPerSec: 0.5 });
  h.tick(0); h.bump();                    // value ~0.34
  h.tick(1);                              // -0.5 → ~0 (clamped)
  assert.equal(h.level, 0, 'heat cools after a quiet second');
  assert.equal(h.onFire, false);
});
