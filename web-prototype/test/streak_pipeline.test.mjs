// streak_pipeline.test.mjs
// Free-throw streak through the REAL pipeline (sim → tracker → engine), swept
// across frame rates and timing jitter. This exists because headless Chrome's
// rAF can run coarse/irregular: an early sim trajectory passed at a steady
// 60 fps but let a brick read as a make under coarse sampling. The sim must be
// sampling-rate robust: every brick resolves as a miss, never as a make.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { gameBySlug, buildRule } from '../js/games.js';
import { CountingEngine } from '../js/countingEngine.js';
import { BallTracker } from '../js/tracker.js';
import { makeSimSource } from '../js/sim.js';

// Deterministic LCG jitter — no Math.random, so failures reproduce exactly.
function makeJitter(seed) {
  let s = seed >>> 0;
  return () => ((s = (s * 1103515245 + 12345) >>> 0), (s % 1000) / 1000 - 0.5);
}

function runPipeline(fps, seconds, jitterAmp = 0) {
  const g = gameBySlug('free-throw-streak');
  const sim = makeSimSource(g);
  const tracker = new BallTracker();
  const eng = new CountingEngine(buildRule({ ...g.ruleSpec }));
  const jitter = makeJitter(fps * 7919);
  let t = 0, makes = 0, misses = 0, longest = 0;
  while (t < seconds) {
    t += (1 / fps) * (1 + jitterAmp * jitter());
    const { ball } = sim.play(t);
    const tracked = tracker.update(ball ? { t, x: ball.x, y: ball.y } : null, t);
    const valid = tracked && tracked.valid;
    const conf = valid && !tracked.coasting ? (ball?.confidence ?? 0.8) : (valid ? 0.5 : 0);
    const before = eng.count;
    eng.update({ t, x: tracked?.x, y: tracked?.y, confidence: conf });
    if (eng.count > before) { makes++; longest = Math.max(longest, eng.count); }
    if (eng.justMissed) misses++;
  }
  return { makes, misses, longest };
}

// 12s covers cycles 0..4: makes at 0,1,2 (streak 3), a brick at 3, a make at 4.
for (const fps of [60, 30, 15, 8, 5]) {
  test(`free-throw pipeline at ${fps} fps: streak builds and the brick resets it`, () => {
    const r = runPipeline(fps, 12);
    assert.ok(r.longest >= 3, `longest streak ${r.longest} should reach 3`);
    assert.ok(r.misses >= 1, `the brick must register as a miss (got ${r.misses})`);
    assert.ok(r.makes <= 4, `the brick must never count as a make (makes=${r.makes})`);
  });
}

test('free-throw pipeline at 30 fps with ±50% frame jitter still resolves the brick as a miss', () => {
  const r = runPipeline(30, 12, 1.0);
  assert.ok(r.misses >= 1, `jittered sampling: miss detected (got ${r.misses})`);
  assert.ok(r.makes <= 4, `jittered sampling: no phantom make (makes=${r.makes})`);
});

test('hoop-count pipeline still mixes swish and rim at 30 fps (regression guard)', () => {
  const g = gameBySlug('hoop-count');
  const sim = makeSimSource(g);
  const tracker = new BallTracker();
  const eng = new CountingEngine(buildRule({ ...g.ruleSpec }));
  for (let i = 0; i <= 30 * 14; i++) {
    const t = i / 30;
    const { ball } = sim.play(t);
    const tracked = tracker.update(ball ? { t, x: ball.x, y: ball.y } : null, t);
    const valid = tracked && tracked.valid;
    const conf = valid && !tracked.coasting ? (ball?.confidence ?? 0.8) : (valid ? 0.5 : 0);
    eng.update({ t, x: tracked?.x, y: tracked?.y, confidence: conf });
  }
  const quals = eng.events.map((e) => e.quality);
  assert.ok(quals.includes('swish') && quals.includes('rim'),
    `expected both qualities, got ${JSON.stringify(quals)}`);
});
