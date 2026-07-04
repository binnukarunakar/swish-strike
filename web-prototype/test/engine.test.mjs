// engine.test.mjs — deterministic unit tests for the JS counting engine.
// Run: node --test   (from apps/swish/web-prototype/)
//
// These mirror ios/SwishStrikeCore/Tests/SwishStrikeCoreTests/CountingEngineTests.swift.
// If you change one suite, change the other and keep both green.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  CountingEngine, zoneCrossDownRule, bounceReversalRule,
} from '../js/countingEngine.js';

// A standard basketball hoop zone: a band near top-center of the frame.
const HOOP = { left: 0.35, top: 0.30, right: 0.65, bottom: 0.42 };

// Helper: build a downward "make" — ball starts above the hoop, lined up, and
// falls straight through to the bottom of frame.
function makeShot(t0, x = 0.5) {
  return [
    { t: t0 + 0.00, x, y: 0.10, confidence: 0.9 }, // above, armed
    { t: t0 + 0.05, x, y: 0.22, confidence: 0.9 },
    { t: t0 + 0.10, x, y: 0.36, confidence: 0.9 }, // inside zone, descending
    { t: t0 + 0.15, x, y: 0.50, confidence: 0.9 }, // crossed below bottom -> make
    { t: t0 + 0.20, x, y: 0.70, confidence: 0.9 },
  ];
}

test('zoneCrossDown: a clean make counts exactly once', () => {
  const e = new CountingEngine(zoneCrossDownRule(HOOP));
  e.feed(makeShot(0));
  assert.equal(e.count, 1);
  assert.equal(e.events.length, 1);
});

test('zoneCrossDown: two makes spaced past the cooldown count twice', () => {
  const e = new CountingEngine(zoneCrossDownRule(HOOP, { cooldown: 1.0 }));
  e.feed(makeShot(0));
  e.feed(makeShot(2.0)); // 2s later, well past cooldown
  assert.equal(e.count, 2);
});

test('zoneCrossDown: a second crossing inside the cooldown does NOT double-count', () => {
  const e = new CountingEngine(zoneCrossDownRule(HOOP, { cooldown: 1.0 }));
  e.feed(makeShot(0));
  e.feed(makeShot(0.3)); // re-cross 0.3s later, inside cooldown
  assert.equal(e.count, 1);
});

test('zoneCrossDown: a rim-out (ball drifts out of the x-band) does NOT count', () => {
  const e = new CountingEngine(zoneCrossDownRule(HOOP));
  // Armed above center, but the ball bounces out to the right and falls outside.
  e.feed([
    { t: 0.00, x: 0.50, y: 0.10, confidence: 0.9 }, // armed
    { t: 0.05, x: 0.62, y: 0.28, confidence: 0.9 },
    { t: 0.10, x: 0.85, y: 0.45, confidence: 0.9 }, // below bottom but OUT of band
    { t: 0.15, x: 0.95, y: 0.70, confidence: 0.9 },
  ]);
  assert.equal(e.count, 0);
});

test('zoneCrossDown: an upward pass (ball thrown up through zone) does NOT count', () => {
  const e = new CountingEngine(zoneCrossDownRule(HOOP));
  // Ball travels UP through the zone (y decreasing) — not a make.
  e.feed([
    { t: 0.00, x: 0.5, y: 0.70, confidence: 0.9 },
    { t: 0.05, x: 0.5, y: 0.50, confidence: 0.9 },
    { t: 0.10, x: 0.5, y: 0.36, confidence: 0.9 },
    { t: 0.15, x: 0.5, y: 0.10, confidence: 0.9 }, // armed only at the end
  ]);
  assert.equal(e.count, 0);
});

test('zoneCrossDown: low-confidence detections are ignored', () => {
  const e = new CountingEngine(zoneCrossDownRule(HOOP));
  const shot = makeShot(0).map((s) => ({ ...s, confidence: 0.1 }));
  e.feed(shot);
  assert.equal(e.count, 0);
});

test('zoneCrossDown: a detector dropout mid-flight still counts the make', () => {
  const e = new CountingEngine(zoneCrossDownRule(HOOP));
  e.feed([
    { t: 0.00, x: 0.5, y: 0.10, confidence: 0.9 },             // armed
    { t: 0.05, x: 0.5, y: 0.30, confidence: 0.0 },             // dropout
    { t: 0.10, x: 0.5, y: 0.50, confidence: 0.9 },             // reappears below -> make
    { t: 0.15, x: 0.5, y: 0.70, confidence: 0.9 },
  ]);
  assert.equal(e.count, 1);
});

test('zoneCrossDown: arming that times out (armWindow) does not count a late drop', () => {
  const e = new CountingEngine(zoneCrossDownRule(HOOP, { armWindow: 0.5 }));
  e.feed([
    { t: 0.0, x: 0.5, y: 0.10, confidence: 0.9 }, // armed at t=0
    // ball hovers above for a long time, arm should expire
    { t: 1.0, x: 0.5, y: 0.36, confidence: 0.9 },
    { t: 1.1, x: 0.5, y: 0.50, confidence: 0.9 }, // crosses, but armed expired
  ]);
  assert.equal(e.count, 0);
});

test('bounceReversal: counts juggle touches, amplitude-gated', () => {
  const e = new CountingEngine(bounceReversalRule({ direction: 'bottom', minAmplitude: 0.15, cooldown: 0.1 }));
  // Simulate 3 juggles: ball goes down to ~0.8 then up to ~0.3, repeated.
  const samples = [];
  let t = 0;
  const apex = 0.3, trough = 0.8;
  for (let rep = 0; rep < 3; rep++) {
    // down to trough
    for (const y of [0.4, 0.6, trough]) { samples.push({ t: (t += 0.05), x: 0.5, y, confidence: 0.9 }); }
    // up to apex
    for (const y of [0.6, 0.4, apex]) { samples.push({ t: (t += 0.05), x: 0.5, y, confidence: 0.9 }); }
  }
  e.feed(samples);
  assert.equal(e.count, 3);
});

test('bounceReversal: micro-jitter below the amplitude threshold does not count', () => {
  const e = new CountingEngine(bounceReversalRule({ direction: 'bottom', minAmplitude: 0.20, cooldown: 0.05 }));
  const samples = [];
  let t = 0;
  // tiny oscillations of ~0.03 amplitude, far below 0.20 threshold
  for (let i = 0; i < 20; i++) {
    const y = 0.5 + (i % 2 === 0 ? 0.015 : -0.015);
    samples.push({ t: (t += 0.05), x: 0.5, y, confidence: 0.9 });
  }
  e.feed(samples);
  assert.equal(e.count, 0);
});

test('reset() clears all state', () => {
  const e = new CountingEngine(zoneCrossDownRule(HOOP));
  e.feed(makeShot(0));
  assert.equal(e.count, 1);
  e.reset();
  assert.equal(e.count, 0);
  assert.equal(e.events.length, 0);
  assert.equal(e.position, null);
});

// --- edge-case hardening -----------------------------------------------------

test('order guard: out-of-order and duplicate timestamps are dropped', () => {
  const e = new CountingEngine(zoneCrossDownRule(HOOP));
  e.feed(makeShot(0));               // count 1, last t = 0.20
  const before = e.count;
  e.update({ t: 0.10, x: 0.5, y: 0.50, confidence: 0.9 }); // older than last -> ignored
  e.update({ t: 0.20, x: 0.5, y: 0.50, confidence: 0.9 }); // duplicate t  -> ignored
  assert.equal(e.count, before);
});

test('non-finite coordinates are treated as misses, never crash', () => {
  const e = new CountingEngine(zoneCrossDownRule(HOOP));
  assert.doesNotThrow(() => {
    e.update({ t: 0.0, x: NaN, y: 0.5, confidence: 0.9 });
    e.update({ t: 0.1, x: 0.5, y: Infinity, confidence: 0.9 });
    e.update({ t: 0.2, x: 0.5, y: 0.5, confidence: NaN });
  });
  assert.equal(e.count, 0);
  e.feed(makeShot(1.0));             // a real make after the garbage still counts
  assert.equal(e.count, 1);
});

test('long detector gap resets the track — the smoothed point does not blend across the occlusion', () => {
  // After a gap > maxGap, the next valid sample becomes the position outright
  // (track reset) rather than an EMA blend with the stale pre-gap point — so no
  // phantom mid-air position (and no crossing) is synthesized across the gap.
  const gapped = new CountingEngine(zoneCrossDownRule(HOOP, { maxGap: 1.0 }));
  gapped.update({ t: 0.0, x: 0.2, y: 0.10, confidence: 0.9 });
  gapped.update({ t: 5.0, x: 0.8, y: 0.90, confidence: 0.9 }); // gap 5s > maxGap -> reset
  assert.ok(Math.abs(gapped.position.x - 0.8) < 1e-9 && Math.abs(gapped.position.y - 0.90) < 1e-9);
  assert.equal(gapped.count, 0);

  // Control: same samples, gap < maxGap -> the engine blends (EMA midpoint).
  const contiguous = new CountingEngine(zoneCrossDownRule(HOOP, { maxGap: 10 }));
  contiguous.update({ t: 0.0, x: 0.2, y: 0.10, confidence: 0.9 });
  contiguous.update({ t: 5.0, x: 0.8, y: 0.90, confidence: 0.9 });
  assert.ok(Math.abs(contiguous.position.x - 0.5) < 1e-9 && Math.abs(contiguous.position.y - 0.5) < 1e-9);
});

test('degenerate (zero-area / inverted) zone never fires', () => {
  const bad = { left: 0.6, top: 0.3, right: 0.4, bottom: 0.2 }; // right<left, bottom<top
  const e = new CountingEngine(zoneCrossDownRule(bad));
  assert.doesNotThrow(() => e.feed(makeShot(0)));
  assert.equal(e.count, 0);
});
