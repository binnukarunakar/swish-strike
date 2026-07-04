// foundation.test.mjs — unit tests for the new pure modules: BallTracker,
// PlayerRegistry, and the camera coach. Run: node --test

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { BallTracker } from '../js/tracker.js';
import { PlayerRegistry } from '../js/players.js';
import { coach } from '../js/coach.js';

// --- BallTracker -------------------------------------------------------------

test('tracker: first fix initializes, second builds velocity', () => {
  const tr = new BallTracker();
  const a = tr.update({ t: 0, x: 0.1, y: 0.5 });
  assert.ok(a.valid && !a.coasting && a.vx === 0);
  const b = tr.update({ t: 0.1, x: 0.2, y: 0.5 });
  assert.ok(b.valid && b.vx > 0); // moving right -> positive vx
});

test('tracker: coasts through misses up to maxCoastFrames, then invalidates', () => {
  const tr = new BallTracker({ maxCoastFrames: 3 });
  tr.update({ t: 0, x: 0.1, y: 0.5 });
  tr.update({ t: 0.1, x: 0.2, y: 0.5 });   // vx > 0
  const c1 = tr.update(null, 0.2);
  assert.ok(c1.valid && c1.coasting && c1.x > 0.15); // predicts forward
  assert.ok(tr.update(null, 0.3).valid);
  assert.ok(tr.update(null, 0.4).valid);             // coastCount == 3
  assert.equal(tr.update(null, 0.5).valid, false);   // coastCount 4 > 3 -> stale
});

// --- PlayerRegistry ----------------------------------------------------------

const box = (x, y) => ({ bbox: { x, y, w: 0.1, h: 0.3 } });

test('players: stable ids across frames, attribute to nearest, per-player streaks', () => {
  const reg = new PlayerRegistry();
  reg.update([box(0.10, 0.30), box(0.60, 0.30)], 0);
  assert.equal(reg.count, 2);
  reg.update([box(0.12, 0.31), box(0.62, 0.31)], 0.1); // small drift -> same ids
  assert.equal(reg.count, 2);

  const left = reg.attribute({ x: 0.16, y: 0.45 });
  const right = reg.attribute({ x: 0.66, y: 0.45 });
  assert.notEqual(left, right);

  reg.recordScore(left); reg.recordScore(left); reg.recordMiss(left);
  const p = reg.stats().find((s) => s.id === left);
  assert.equal(p.count, 2);
  assert.equal(p.streak, 0);   // miss reset the streak
  assert.equal(p.best, 2);     // but best run is remembered
});

test('players: a long-unseen player is forgotten', () => {
  const reg = new PlayerRegistry({ forgetAfter: 1.5 });
  reg.update([box(0.10, 0.30), box(0.60, 0.30)], 0);
  reg.update([box(0.12, 0.31)], 5.0); // right player gone for ~5s
  assert.equal(reg.count, 1);
});

// --- coach -------------------------------------------------------------------

test('coach: no target -> searching', () => {
  const r = coach({ targetVisible: false, targetBox: null, brightness: 0.5 });
  assert.equal(r.status, 'searching');
  assert.equal(r.ready, false);
});

test('coach: tiny target -> move closer', () => {
  const r = coach({ targetVisible: true, targetBox: { x: 0.48, y: 0.45, w: 0.04, h: 0.04 }, brightness: 0.5 });
  assert.equal(r.ready, false);
  assert.match(r.primary, /closer/i);
});

test('coach: well-framed + bright + body -> ready', () => {
  const r = coach({ targetVisible: true, targetBox: { x: 0.4, y: 0.4, w: 0.2, h: 0.12 }, brightness: 0.5, needsBody: false });
  assert.equal(r.ready, true);
  assert.equal(r.status, 'ready');
});

test('coach: low light is flagged', () => {
  const r = coach({ targetVisible: true, targetBox: { x: 0.4, y: 0.4, w: 0.2, h: 0.12 }, brightness: 0.05 });
  assert.equal(r.ready, false);
  assert.ok(r.hints.some((h) => /dark/i.test(h)));
});

test('coach: body-required game asks you to step back when no body is seen', () => {
  const r = coach({ targetVisible: true, targetBox: { x: 0.4, y: 0.4, w: 0.2, h: 0.12 }, brightness: 0.5, needsBody: true, bodyVisible: false });
  assert.equal(r.ready, false);
  assert.ok(r.hints.some((h) => /whole body/i.test(h)));
});
