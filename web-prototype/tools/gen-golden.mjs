// gen-golden.mjs
// ----------------------------------------------------------------------------
// Generates test/golden.fixtures.json — a frozen set of (rule, sample-stream,
// expected-output) cases produced by running the JS engine. The SAME file is then
// replayed through:
//   • the JS engine (test/parity.test.mjs)        — regression guard
//   • the Swift engine (SwishStrikeParity executable)    — cross-language parity proof
// If Swift ever diverges from this JS-frozen golden, SwishStrikeParity fails. That is a
// stronger guarantee than two independently-written suites that merely agree.
//
// Run: node tools/gen-golden.mjs   (rewrites test/golden.fixtures.json)
// ----------------------------------------------------------------------------

import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { CountingEngine, zoneCrossDownRule, bounceReversalRule } from '../js/countingEngine.js';

const HOOP = { left: 0.35, top: 0.30, right: 0.65, bottom: 0.42 };
const s = (t, x, y, c) => ({ t, x, y, c }); // compact sample {t,x,y,confidence}

function makeShot(t0, x = 0.5) {
  return [s(t0, x, 0.10, 0.9), s(t0 + 0.05, x, 0.22, 0.9), s(t0 + 0.10, x, 0.36, 0.9),
          s(t0 + 0.15, x, 0.50, 0.9), s(t0 + 0.20, x, 0.70, 0.9)];
}
function juggles(n) {
  const out = []; let t = 0;
  for (let i = 0; i < n; i++) {
    for (const y of [0.4, 0.6, 0.8]) out.push(s((t += 0.05), 0.5, y, 0.9));
    for (const y of [0.6, 0.4, 0.3]) out.push(s((t += 0.05), 0.5, y, 0.9));
  }
  return out;
}

// Each scenario: a serializable rule spec + a sample stream. Expected output is
// computed below by the JS engine — the golden the Swift engine must reproduce.
const scenarios = [
  { name: 'clean-make', rule: { kind: 'zoneCrossDown', zone: HOOP, opts: { cooldown: 0.9 } },
    samples: makeShot(0) },
  { name: 'two-makes-past-cooldown', rule: { kind: 'zoneCrossDown', zone: HOOP, opts: { cooldown: 1.0 } },
    samples: [...makeShot(0), ...makeShot(2.0)] },
  { name: 'cooldown-blocks-recross', rule: { kind: 'zoneCrossDown', zone: HOOP, opts: { cooldown: 1.0 } },
    samples: [...makeShot(0), ...makeShot(0.3)] },
  { name: 'rim-out', rule: { kind: 'zoneCrossDown', zone: HOOP, opts: {} },
    samples: [s(0.0, 0.50, 0.10, 0.9), s(0.05, 0.62, 0.28, 0.9), s(0.10, 0.85, 0.45, 0.9), s(0.15, 0.95, 0.70, 0.9)] },
  { name: 'upward-pass', rule: { kind: 'zoneCrossDown', zone: HOOP, opts: {} },
    samples: [s(0.0, 0.5, 0.70, 0.9), s(0.05, 0.5, 0.50, 0.9), s(0.10, 0.5, 0.36, 0.9), s(0.15, 0.5, 0.10, 0.9)] },
  { name: 'dropout-mid-flight', rule: { kind: 'zoneCrossDown', zone: HOOP, opts: {} },
    samples: [s(0.0, 0.5, 0.10, 0.9), s(0.05, 0.5, 0.30, 0.0), s(0.10, 0.5, 0.50, 0.9), s(0.15, 0.5, 0.70, 0.9)] },
  { name: 'order-guard-stale-frames', rule: { kind: 'zoneCrossDown', zone: HOOP, opts: { cooldown: 1.0 } },
    samples: [...makeShot(0), s(0.10, 0.5, 0.50, 0.9), s(0.20, 0.5, 0.50, 0.9)] },
  { name: 'degenerate-zone', rule: { kind: 'zoneCrossDown', zone: { left: 0.6, top: 0.3, right: 0.4, bottom: 0.2 }, opts: {} },
    samples: makeShot(0) },
  { name: 'juggle-three', rule: { kind: 'bounceReversal', opts: { direction: 'bottom', minAmplitude: 0.15, cooldown: 0.1 } },
    samples: juggles(3) },
  { name: 'jitter-none', rule: { kind: 'bounceReversal', opts: { direction: 'bottom', minAmplitude: 0.20, cooldown: 0.05 } },
    samples: Array.from({ length: 20 }, (_, i) => s((i + 1) * 0.05, 0.5, 0.5 + (i % 2 === 0 ? 0.015 : -0.015), 0.9)) },
];

function buildRule(spec) {
  if (spec.kind === 'zoneCrossDown') return zoneCrossDownRule(spec.zone, spec.opts || {});
  if (spec.kind === 'bounceReversal') return bounceReversalRule(spec.opts || {});
  throw new Error(`unknown rule kind ${spec.kind}`);
}

const out = scenarios.map((sc) => {
  const e = new CountingEngine(buildRule(sc.rule));
  for (const sm of sc.samples) e.update({ t: sm.t, x: sm.x, y: sm.y, confidence: sm.c });
  return { ...sc, expectedCount: e.count, expectedEventTimes: e.events.map((ev) => ev.t) };
});

const here = dirname(fileURLToPath(import.meta.url));
const file = resolve(here, '../test/golden.fixtures.json');
writeFileSync(file, JSON.stringify({ generatedBy: 'gen-golden.mjs', scenarios: out }, null, 2) + '\n');
console.log(`wrote ${out.length} golden scenarios -> test/golden.fixtures.json`);
for (const o of out) console.log(`  ${o.name}: count=${o.expectedCount}, events=[${o.expectedEventTimes.map((t) => t.toFixed(2)).join(', ')}]`);
