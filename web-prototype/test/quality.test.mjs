// quality.test.mjs
// Shot-quality classification for zoneCrossDown (basketball swish vs rim rattle).
// The label is metadata attached to the score event; it must NOT change the count,
// so these tests assert BOTH the quality label and that a make still counts once.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CountingEngine, zoneCrossDownRule } from '../js/countingEngine.js';

// The default basketball hoop zone (mirrors games.js ZONES.hoop). Center x = 0.5.
const HOOP = { left: 0.36, top: 0.26, right: 0.64, bottom: 0.38 };
const rule = () => zoneCrossDownRule(HOOP, { cooldown: 0.9 });

/** Feed a list of [t, x, y] samples (confidence implied high) and return the engine. */
function play(samples) {
  const e = new CountingEngine(rule());
  for (const [t, x, y] of samples) e.update({ t, x, y, confidence: 0.95 });
  return e;
}

test('a centered, monotonic drop is classified as a swish', () => {
  const e = play([
    [0.1, 0.5, 0.08], [0.2, 0.5, 0.12], [0.3, 0.5, 0.20],
    [0.4, 0.5, 0.30], [0.5, 0.5, 0.40], [0.6, 0.5, 0.55],
  ]);
  assert.equal(e.count, 1, 'a clean make still counts exactly once');
  assert.equal(e.lastEvent.quality, 'swish');
  assert.ok(e.lastEvent.centerError <= 0.5, 'swish crosses through the central half');
});

test('an off-center make (near the rim edge) is classified as a rim rattle', () => {
  // x = 0.62 sits near the right edge of the 0.36–0.64 zone: centerError ≈ 0.86.
  const e = play([
    [0.1, 0.62, 0.08], [0.2, 0.62, 0.12], [0.3, 0.62, 0.20],
    [0.4, 0.62, 0.30], [0.5, 0.62, 0.40], [0.6, 0.62, 0.55],
  ]);
  assert.equal(e.count, 1, 'an off-center make is still a make — count unchanged');
  assert.equal(e.lastEvent.quality, 'rim');
  assert.ok(e.lastEvent.centerError > 0.5);
});

test('a centered make that pops back up off the rim is classified as a rim rattle', () => {
  // Dead-center x, but the ball rises (y decreases) mid-descent before dropping
  // through — a down→up reversal, the signature of a rim contact.
  const e = play([
    [0.1, 0.5, 0.08], [0.2, 0.5, 0.12], [0.3, 0.5, 0.20], [0.4, 0.5, 0.30],
    [0.5, 0.5, 0.40], [0.6, 0.5, 0.30], /* pops up */ [0.7, 0.5, 0.55], /* drops in */
  ]);
  assert.equal(e.count, 1, 'a rattle-in still counts exactly once');
  assert.equal(e.lastEvent.quality, 'rim');
  assert.ok(e.lastEvent.centerError <= 0.5, 'rim here is from the pop-up, not off-center');
});

test('quality never changes the count: swish and rim sequences both score one', () => {
  const swish = play([[0.1, 0.5, 0.08], [0.2, 0.5, 0.20], [0.3, 0.5, 0.40], [0.4, 0.5, 0.55]]);
  const rim = play([[0.1, 0.62, 0.08], [0.2, 0.62, 0.20], [0.3, 0.62, 0.40], [0.4, 0.62, 0.55]]);
  assert.equal(swish.count, rim.count, 'the count is identical regardless of shot quality');
});
