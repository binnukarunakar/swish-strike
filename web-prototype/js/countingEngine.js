// countingEngine.js
// ----------------------------------------------------------------------------
// Swish Strike — the pure, deterministic counting engine.
//
// This is the brain of the app and the reason the whole thing is testable. It
// has NO knowledge of cameras, the DOM, or any ML model. You feed it a stream of
// ball positions (normalized 0..1 coordinates, y pointing DOWN like image/screen
// space) and it tells you when a "score event" happens — a basketball going
// through the hoop, a soccer ball crossing the goal line, a juggle touch, etc.
//
// The exact same logic exists in Swift at ios/SwishStrikeCore/Sources/SwishStrikeCore/
// CountingEngine.swift. Same input sequence MUST yield the same count in both.
// That contract is guarded three ways: engine.test.mjs, CountingEngineTests.swift,
// and a SHARED golden trace (test/golden.fixtures.json) replayed through both
// languages. Do not change behavior in one without the other.
//
// Robustness (see the guards in update()): out-of-order/duplicate frames are
// dropped, non-finite coordinates are treated as misses, a long detector gap
// resets the track so no phantom crossing is synthesized across an occlusion, and
// a degenerate (zero-area) zone simply never fires.
// ----------------------------------------------------------------------------

export const RuleType = Object.freeze({
  // Ball passes downward through a target zone (hoop, goal, bucket, cornhole).
  ZONE_CROSS_DOWN: 'zoneCrossDown',
  // Like zoneCrossDown, but the count is a CONSECUTIVE streak: a make increments
  // it, a detected miss resets it to 0 (free-throw streak).
  ZONE_STREAK: 'zoneStreak',
  // Ball oscillates and we count amplitude-gated reversals (juggle, dribble, rally).
  BOUNCE_REVERSAL: 'bounceReversal',
});

export const DEFAULTS = Object.freeze({
  smoothingAlpha: 0.5, // EMA factor (0..1). Higher = snappier, lower = smoother.
  minConfidence: 0.30, // detections below this are ignored.
  maxGap: 1.5,         // seconds; a longer gap between valid samples resets the track.
});

const isFiniteNum = (v) => typeof v === 'number' && Number.isFinite(v);

// --- rule builders -----------------------------------------------------------

/**
 * zoneCrossDown rule. `zone` is {left, top, right, bottom} in normalized coords.
 * Fires when the ball, after being seen above the zone and horizontally aligned,
 * crosses below the zone's bottom edge while moving downward — within `armWindow`
 * seconds and respecting `cooldown` seconds between counts.
 */
export function zoneCrossDownRule(zone, opts = {}) {
  return {
    type: RuleType.ZONE_CROSS_DOWN,
    zone: { left: zone.left, top: zone.top, right: zone.right, bottom: zone.bottom },
    xTolerance: opts.xTolerance ?? 0.05,
    armWindow: opts.armWindow ?? 1.5,
    cooldown: opts.cooldown ?? 1.0,
    smoothingAlpha: opts.smoothingAlpha ?? DEFAULTS.smoothingAlpha,
    minConfidence: opts.minConfidence ?? DEFAULTS.minConfidence,
    maxGap: opts.maxGap ?? DEFAULTS.maxGap,
  };
}

/**
 * zoneStreak rule. Detects makes exactly like zoneCrossDown, but the engine count
 * tracks the CONSECUTIVE streak: a make increments it, and a miss (the ball, after
 * being aimed at the target, falls past it — more than `missMargin` below the
 * zone — without scoring) resets it to 0. Used by Free-Throw Streak.
 */
export function zoneStreakRule(zone, opts = {}) {
  const rule = zoneCrossDownRule(zone, opts);
  rule.type = RuleType.ZONE_STREAK;
  rule.missMargin = opts.missMargin ?? 0.18; // how far below the zone counts as a miss
  return rule;
}

/**
 * bounceReversal rule. `direction` is 'bottom' (count troughs — juggle touch /
 * floor bounce) or 'top' (count apexes). `minAmplitude` is the normalized
 * vertical travel required after an extreme before a rep is confirmed (rejects
 * jitter). `cooldown` is the minimum seconds between counts.
 */
export function bounceReversalRule(opts = {}) {
  return {
    type: RuleType.BOUNCE_REVERSAL,
    direction: opts.direction ?? 'bottom',
    minAmplitude: opts.minAmplitude ?? 0.12,
    cooldown: opts.cooldown ?? 0.25,
    smoothingAlpha: opts.smoothingAlpha ?? DEFAULTS.smoothingAlpha,
    minConfidence: opts.minConfidence ?? DEFAULTS.minConfidence,
    maxGap: opts.maxGap ?? DEFAULTS.maxGap,
  };
}

// --- the engine --------------------------------------------------------------

export class CountingEngine {
  constructor(rule) {
    if (!rule || !rule.type) throw new Error('CountingEngine needs a rule');
    this.rule = rule;
    this.reset();
  }

  reset() {
    this.count = 0;
    this.events = [];            // [{t, count, quality?, centerError?}] score events
    this.lastEvent = null;       // most recent score event (incl. shot quality)
    this.justMissed = false;     // true only on the update where a streak miss resolved
    this._lastT = -Infinity;     // last accepted timestamp (order guard)
    this._lastValidT = -Infinity;// last VALID-measurement timestamp (gap guard)
    this._lastCountT = -Infinity;
    this._lastQuality = null;    // shot quality computed at fire, consumed on push
    this._resetTrack();
    return this;
  }

  /** Clears only the per-frame tracking state (not the count/history). */
  _resetTrack() {
    this._sx = null; this._sy = null; this._py = null;
    this._armed = false; this._armedT = -Infinity;     // zoneCrossDown
    this._attemptActive = false;                       // zoneStreak: a shot is in flight
    this._descentReversals = 0; this._lastDySign = 0;  // shot-quality (swish vs rim)
    this._extremeVal = null; this._sawApproach = false; // bounceReversal
  }

  /** Smoothed ball position, or null if nothing seen yet. */
  get position() {
    return this._sx == null ? null : { x: this._sx, y: this._sy };
  }

  /**
   * Feed one sample: { t, x, y, confidence } in normalized coords (y down).
   * Returns true iff a score event fired this sample.
   */
  update(sample) {
    if (!sample) return false;
    const r = this.rule;
    const t = sample.t;
    this.justMissed = false; // reset every accepted/rejected frame (before any early return below)

    // Order guard: drop out-of-order or duplicate frames (also rejects NaN t).
    if (!(t > this._lastT)) return false;
    this._lastT = t;

    // Long-gap discontinuity: a detector silence longer than maxGap means we
    // can't trust the previous point — reset the track so no crossing is
    // synthesized across the gap. (The count/history are preserved.)
    if (this._lastValidT !== -Infinity && t - this._lastValidT > r.maxGap) {
      this._resetTrack();
    }

    // Validity gate: need finite x/y and (if provided) finite confidence ≥ floor.
    const confOK = sample.confidence == null
      || (isFiniteNum(sample.confidence) && sample.confidence >= r.minConfidence);
    if (!(isFiniteNum(sample.x) && isFiniteNum(sample.y) && confOK)) {
      return false; // a miss — state is held, time has advanced
    }
    this._lastValidT = t;

    const a = r.smoothingAlpha;
    this._sx = this._sx == null ? sample.x : a * sample.x + (1 - a) * this._sx;
    this._sy = this._sy == null ? sample.y : a * sample.y + (1 - a) * this._sy;

    let fired = false, missed = false;
    if (r.type === RuleType.ZONE_CROSS_DOWN) fired = this._detectMake(t);
    else if (r.type === RuleType.ZONE_STREAK) {
      const res = this._zoneStreak(t);
      fired = res === 'make'; missed = res === 'miss';
    }
    else if (r.type === RuleType.BOUNCE_REVERSAL) fired = this._bounceReversal(t);

    this._py = this._sy;
    if (fired) {
      this.count += 1;
      this._lastCountT = t;
      const ev = { t, count: this.count };
      if (this._lastQuality) {
        ev.quality = this._lastQuality.quality;
        ev.centerError = this._lastQuality.centerError;
        this._lastQuality = null;
      }
      this.events.push(ev);
      this.lastEvent = ev;
    } else if (missed) {
      this.count = 0; // streak broken — reset, but do NOT set a cooldown (next shot is fair)
      const ev = { t, count: 0, type: 'miss' };
      this.events.push(ev);
      this.lastEvent = ev;
      this.justMissed = true;
    }
    return fired;
  }

  /** Convenience: feed an array, return final count. */
  feed(samples) {
    for (const s of samples) this.update(s);
    return this.count;
  }

  // Detects a single make through the zone (shared by zoneCrossDown and zoneStreak).
  // Returns true on a make and stashes its swish/rim quality. Behavior is unchanged
  // from the original zoneCrossDown, so the golden parity stays exact.
  _detectMake(t) {
    const r = this.rule, z = r.zone;
    if (z.right <= z.left || z.bottom <= z.top) return false; // degenerate zone never fires

    const inBand = this._sx >= z.left - r.xTolerance &&
                   this._sx <= z.right + r.xTolerance;

    // Arm when first seen above the zone and aligned; reset shot-quality tracking
    // on the rising edge so each attempt is classified independently.
    if (inBand && this._sy < z.top) {
      if (!this._armed) { this._descentReversals = 0; this._lastDySign = 0; }
      this._armed = true; this._armedT = t;
    }
    if (this._armed && t - this._armedT > r.armWindow) this._armed = false;

    // Shot-quality signal: while tracking a descent, count vertical reversals.
    // A clean swish falls monotonically; a rim rattle pops the ball back up
    // before it drops, so a down→up flip is evidence of a rim contact.
    if (this._armed && this._py != null) {
      const dy = this._sy - this._py;
      const sign = dy > 1e-4 ? 1 : (dy < -1e-4 ? -1 : 0);
      if (sign !== 0) {
        if (this._lastDySign === 1 && sign === -1) this._descentReversals += 1;
        this._lastDySign = sign;
      }
    }

    const movingDown = this._py == null ? true : this._sy > this._py;
    const crossedBelow = this._sy > z.bottom;
    const cooledDown = t - this._lastCountT > r.cooldown;

    if (this._armed && inBand && crossedBelow && movingDown && cooledDown &&
        t - this._armedT <= r.armWindow) {
      this._armed = false;
      this._lastQuality = this._classifyShot(z);
      return true;
    }
    return false;
  }

  /**
   * Classify a made basket at the crossing point as a clean 'swish' or a 'rim'
   * rattle. Pure metadata — it does NOT affect whether/when a score fires, so the
   * count (and the cross-language golden parity) is unchanged. A make is a swish
   * when it crosses through the central half of the zone with no rim pop-up.
   */
  _classifyShot(z) {
    const cx = (z.left + z.right) / 2;
    const halfW = ((z.right - z.left) / 2) || 1e-6;
    const centerError = Math.abs(this._sx - cx) / halfW; // 0 = dead center, 1 = at the edge
    const clean = centerError <= 0.5 && this._descentReversals === 0;
    return { quality: clean ? 'swish' : 'rim', centerError };
  }

  // zoneStreak: detect a make (via _detectMake) and, otherwise, a miss — a shot
  // that armed (was aimed at the rim) but then fell more than `missMargin` past the
  // zone without scoring. Returns 'make' | 'miss' | null.
  _zoneStreak(t) {
    const z = this.rule.zone;
    if (z.right <= z.left || z.bottom <= z.top) return null;
    const wasArmed = this._armed;
    const made = this._detectMake(t);
    if (this._armed && !wasArmed) this._attemptActive = true; // a shot just went up at the rim
    if (made) { this._attemptActive = false; return 'make'; }
    if (this._attemptActive && this._sy > z.bottom + this.rule.missMargin) {
      this._attemptActive = false; // the ball fell past the rim without going in
      return 'miss';
    }
    return null;
  }

  _bounceReversal(t) {
    const r = this.rule;
    const dirSign = r.direction === 'bottom' ? 1 : -1; // +1 tracks troughs, -1 apexes
    const val = dirSign * this._sy;

    if (this._extremeVal == null || val > this._extremeVal) this._extremeVal = val;
    if (this._py != null) {
      const towardExtreme = (this._sy - this._py) * dirSign;
      if (towardExtreme > 0) this._sawApproach = true;
    }

    const retreat = this._extremeVal == null ? 0 : this._extremeVal - val;
    const cooledDown = t - this._lastCountT > r.cooldown;
    if (this._sawApproach && retreat >= r.minAmplitude && cooledDown) {
      this._extremeVal = val; // re-baseline at the confirmation point
      return true;
    }
    return false;
  }
}

// Single import surface for the app + tests.
export default { RuleType, DEFAULTS, CountingEngine, zoneCrossDownRule, zoneStreakRule, bounceReversalRule };
