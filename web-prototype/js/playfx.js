// playfx.js
// ----------------------------------------------------------------------------
// Play-phase effects that are deliberately NOT part of the pure counting engine:
//   • TrailBuffer — a short, time-windowed history of ball positions, drawn as a
//     fading "comet" behind the ball and snapshotted as the made-shot arc for the
//     instant replay + share card.
//   • Heat — a decaying meter that rises with each score and cools over time, so
//     rapid scoring lights the screen up ("on fire"). It rewards a hot streak
//     without needing a miss signal the engine doesn't have.
// Both are pure data structures (no DOM, no engine coupling) so they unit-test.
// ----------------------------------------------------------------------------

const isNum = (v) => typeof v === 'number' && Number.isFinite(v);

export class TrailBuffer {
  constructor({ maxAgeMs = 850, max = 64 } = {}) {
    this.maxAgeMs = maxAgeMs; this.max = max; this.pts = [];
  }
  push(nowMs, x, y) {
    if (!isNum(x) || !isNum(y)) return;
    this.pts.push({ t: nowMs, x, y });
    if (this.pts.length > this.max) this.pts.shift();
  }
  /** Points within the fade window, oldest→newest, each with age 0..1 (1 = freshest). */
  live(nowMs) {
    const out = [];
    for (const p of this.pts) {
      const age = (nowMs - p.t) / this.maxAgeMs;
      if (age <= 1) out.push({ x: p.x, y: p.y, fade: Math.min(1, 1 - age) }); // clamp: a point stamped ahead of now (clock skew) is capped at full freshness — mirrors PlayFX.swift
    }
    return out;
  }
  /** Snapshot the recent arc (normalized points) for replay + share. */
  snapshotArc(nowMs, spanMs = 1400) {
    return this.pts.filter((p) => nowMs - p.t <= spanMs).map((p) => ({ x: p.x, y: p.y }));
  }
  clear() { this.pts = []; }
}

export class Heat {
  constructor({ perScore = 0.34, decayPerSec = 0.5, max = 1.4 } = {}) {
    this.perScore = perScore; this.decayPerSec = decayPerSec; this.max = max;
    this.value = 0; this._t = null;
  }
  bump() { this.value = Math.min(this.max, this.value + this.perScore); }
  /** Advance decay to nowSec; returns the current 0..1 level. */
  tick(nowSec) {
    if (this._t != null && nowSec > this._t) {
      this.value = Math.max(0, this.value - (nowSec - this._t) * this.decayPerSec);
    }
    this._t = nowSec;
    return this.level;
  }
  get level() { return Math.min(1, this.value); }   // 0..1 for rendering
  get onFire() { return this.value >= 1; }
  reset() { this.value = 0; this._t = null; }
}

export default { TrailBuffer, Heat };
