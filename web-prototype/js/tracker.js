// tracker.js
// ----------------------------------------------------------------------------
// BallTracker — an alpha-beta ("Kalman-lite") filter that turns noisy, gappy
// per-frame ball detections into a smooth position + velocity, and COASTS
// (predicts) through short detector dropouts/occlusions. Pure and deterministic
// so it unit-tests in node. It sits between the detector and the counting engine:
//   detection -> tracker.update() -> {x,y,vx,vy,valid,coasting} -> engine
// The velocity it produces also drives the speed radar and the coach.
// ----------------------------------------------------------------------------

export class BallTracker {
  constructor({ alpha = 0.5, beta = 0.25, maxCoastFrames = 6 } = {}) {
    this.alpha = alpha;       // position correction gain
    this.beta = beta;         // velocity correction gain
    this.maxCoastFrames = maxCoastFrames;
    this.reset();
  }

  reset() {
    this.x = null; this.y = null;
    this.vx = 0; this.vy = 0;
    this.lastT = null;
    this.coastCount = 0;
    return this;
  }

  /**
   * @param {{t:number,x:number,y:number}|null} meas  measurement, or null for a miss
   * @returns {{x:number,y:number,vx:number,vy:number,valid:boolean,coasting:boolean,t:number}|null}
   */
  update(meas, t) {
    const now = meas ? meas.t : t;
    if (now == null) return null;

    // First fix.
    if (this.x == null) {
      if (!meas) return null;
      this.x = meas.x; this.y = meas.y; this.vx = 0; this.vy = 0;
      this.lastT = now; this.coastCount = 0;
      return { x: this.x, y: this.y, vx: 0, vy: 0, valid: true, coasting: false, t: now };
    }

    const dt = Math.max(1e-3, now - this.lastT);
    // Predict.
    const px = this.x + this.vx * dt;
    const py = this.y + this.vy * dt;

    if (meas) {
      const rx = meas.x - px, ry = meas.y - py;
      this.x = px + this.alpha * rx;
      this.y = py + this.alpha * ry;
      this.vx += (this.beta / dt) * rx;
      this.vy += (this.beta / dt) * ry;
      this.coastCount = 0;
      this.lastT = now;
      return { x: this.x, y: this.y, vx: this.vx, vy: this.vy, valid: true, coasting: false, t: now };
    }

    // Miss: coast on the prediction.
    this.x = px; this.y = py;
    this.coastCount += 1;
    this.lastT = now;
    const valid = this.coastCount <= this.maxCoastFrames;
    if (!valid) this.reset(); // track is stale — drop it so we don't bridge a long gap
    return { x: px, y: py, vx: this.vx, vy: this.vy, valid, coasting: true, t: now };
  }

  /** Current speed in normalized units/second. */
  get speed() { return Math.hypot(this.vx, this.vy); }
}

export default { BallTracker };
