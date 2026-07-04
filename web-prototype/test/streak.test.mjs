// streak.test.mjs
// zoneStreak (Free-Throw Streak): the count is a CONSECUTIVE streak — makes
// increment it, a detected miss resets it to 0. A miss is a shot that armed (was
// aimed at the rim) then fell past the zone without scoring.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CountingEngine, zoneStreakRule } from '../js/countingEngine.js';

const HOOP = { left: 0.36, top: 0.26, right: 0.64, bottom: 0.38 }; // center x = 0.5
const rule = () => zoneStreakRule(HOOP, { cooldown: 0.4, missMargin: 0.18 });

// A clean make centered on the rim, starting at time `t0`.
function make(e, t0) {
  for (const [dt, y] of [[0, 0.08], [0.05, 0.20], [0.10, 0.40], [0.15, 0.56]]) {
    e.update({ t: t0 + dt, x: 0.5, y, confidence: 0.95 });
  }
}
// A miss: arms above the rim, then drifts OUT of the band and falls well past it.
// (Enough descent frames for the EMA-smoothed y to clear the miss line.)
function miss(e, t0) {
  const pts = [[0, 0.5, 0.08], [0.05, 0.62, 0.20], [0.10, 0.80, 0.40],
               [0.15, 0.85, 0.60], [0.20, 0.88, 0.78], [0.25, 0.90, 0.92]];
  for (const [dt, x, y] of pts) e.update({ t: t0 + dt, x, y, confidence: 0.95 });
}

test('consecutive makes build the streak', () => {
  const e = new CountingEngine(rule());
  make(e, 0); make(e, 1); make(e, 2);
  assert.equal(e.count, 3, 'three in a row = streak of 3');
  assert.equal(e.justMissed, false);
});

test('a miss resets the streak to zero', () => {
  const e = new CountingEngine(rule());
  make(e, 0); make(e, 1);
  assert.equal(e.count, 2);
  miss(e, 2);
  assert.equal(e.count, 0, 'the miss broke the streak');
  assert.equal(e.lastEvent.type, 'miss');
});

test('the streak rebuilds after a miss', () => {
  const e = new CountingEngine(rule());
  make(e, 0); make(e, 1); miss(e, 2); make(e, 3); make(e, 4);
  assert.equal(e.count, 2, 'two makes after the reset');
});

test('a make is still classified swish vs rim in streak mode', () => {
  const e = new CountingEngine(rule());
  make(e, 0); // centered
  assert.equal(e.lastEvent.quality, 'swish');
});

test('justMissed is only true on the exact frame the miss resolves', () => {
  const e = new CountingEngine(rule());
  make(e, 0);
  let missFrames = 0;
  const pts = [[2.0, 0.5, 0.08], [2.05, 0.62, 0.20], [2.10, 0.80, 0.40], [2.15, 0.85, 0.62], [2.20, 0.86, 0.7]];
  for (const [t, x, y] of pts) { e.update({ t, x, y, confidence: 0.95 }); if (e.justMissed) missFrames++; }
  assert.equal(missFrames, 1, 'the miss fires exactly once, not every frame after');
  assert.equal(e.count, 0);
});
