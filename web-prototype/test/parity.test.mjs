// parity.test.mjs — replays the shared golden trace through the JS engine and
// asserts it matches the frozen expected output. The Swift SwishStrikeParity executable
// replays the SAME golden.fixtures.json through the Swift engine; both passing is
// the cross-language parity guarantee. Regenerate the golden with
// `node tools/gen-golden.mjs` if you intentionally change engine behavior.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  CountingEngine, zoneCrossDownRule, bounceReversalRule,
} from '../js/countingEngine.js';

const golden = JSON.parse(readFileSync(new URL('./golden.fixtures.json', import.meta.url)));

function buildRule(spec) {
  if (spec.kind === 'zoneCrossDown') return zoneCrossDownRule(spec.zone, spec.opts || {});
  if (spec.kind === 'bounceReversal') return bounceReversalRule(spec.opts || {});
  throw new Error(`unknown rule kind ${spec.kind}`);
}

for (const sc of golden.scenarios) {
  test(`golden parity (JS): ${sc.name}`, () => {
    const e = new CountingEngine(buildRule(sc.rule));
    for (const sm of sc.samples) e.update({ t: sm.t, x: sm.x, y: sm.y, confidence: sm.c });
    assert.equal(e.count, sc.expectedCount, 'count');
    const times = e.events.map((ev) => ev.t);
    assert.equal(times.length, sc.expectedEventTimes.length, 'event count');
    for (let i = 0; i < times.length; i++) {
      assert.ok(Math.abs(times[i] - sc.expectedEventTimes[i]) < 1e-9, `event ${i} time`);
    }
  });
}
