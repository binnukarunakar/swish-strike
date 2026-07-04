// vision/ballDetector.js
// ----------------------------------------------------------------------------
// HybridBallDetector — the real on-device ball detector for camera mode. It fuses
// three signals (research: a generic model alone is weak on small/fast balls):
//   1. COLOR  — HSV blob of the ball's known hue (orange basketball). Cheap, robust.
//   2. MOTION — frame differencing, to catch a fast/blurred ball color misses.
//   3. MODEL  — COCO-SSD 'sports ball' (throttled), to confirm/recover.
// It downscales each frame to a small offscreen canvas, runs the cheap signals
// every frame and the model occasionally, and returns one best normalized
// top-left {x,y,confidence,source} — or null. The classical signals it uses
// (color.js, motion.js) are unit-tested headlessly.
// ----------------------------------------------------------------------------

import { detectColorBlob, HUES } from './color.js';
import { motionCentroid } from './motion.js';

const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);

export class HybridBallDetector {
  constructor({ hue = 'orange', useModel = true, modelEvery = 5, longEdge = 192 } = {}) {
    this.hue = hue;
    this.useModel = useModel;
    this.modelEvery = modelEvery;     // run COCO every Nth frame
    this.longEdge = longEdge;
    this.model = null;
    this.frame = 0;
    this.prev = null;                 // previous ImageData (for motion)
    this._lastModel = null;           // last model detection {x,y,confidence,t}
    this._canvas = null; this._ctx = null;
    // a ball should be a small-ish blob; reject huge regions (background) and specks
    this.ballMinArea = 0.0006; this.ballMaxArea = 0.22; this.motionMaxArea = 0.35;
  }

  async load() {
    if (this.useModel && typeof window !== 'undefined' && window.cocoSsd && window.tf) {
      try {
        if (window.tf.setBackend) { try { await window.tf.setBackend('webgl'); } catch {} }
        this.model = await window.cocoSsd.load({ base: 'lite_mobilenet_v2' });
      } catch { this.model = null; }
    }
    return true;
  }

  _grab(video) {
    const vw = video.videoWidth || 640, vh = video.videoHeight || 480;
    const scale = this.longEdge / Math.max(vw, vh);
    const w = Math.max(2, Math.round(vw * scale)), h = Math.max(2, Math.round(vh * scale));
    if (!this._canvas) {
      this._canvas = document.createElement('canvas');
      this._ctx = this._canvas.getContext('2d', { willReadFrequently: true });
    }
    if (this._canvas.width !== w) { this._canvas.width = w; this._canvas.height = h; }
    this._ctx.drawImage(video, 0, 0, w, h);
    return this._ctx.getImageData(0, 0, w, h);
  }

  /** Run COCO on the full video (async, throttled). Updates this._lastModel. */
  async _runModel(video, t) {
    if (!this.model) return;
    try {
      const preds = await this.model.detect(video, 5);
      const balls = preds.filter((p) => p.class === 'sports ball');
      if (!balls.length) return;
      const w = video.videoWidth || 1, h = video.videoHeight || 1;
      const b = balls.reduce((a, c) => (c.score > a.score ? c : a));
      this._lastModel = { x: (b.bbox[0] + b.bbox[2] / 2) / w, y: (b.bbox[1] + b.bbox[3] / 2) / h, confidence: b.score, t };
    } catch { /* ignore */ }
  }

  /**
   * @returns {{x,y,confidence,source}|null} normalized top-left
   */
  async detect(video, t) {
    if (!video || video.readyState < 2) return null;
    const img = this._grab(video);
    const color = detectColorBlob(img, HUES[this.hue] || HUES.orange);
    const motion = this.prev ? motionCentroid(this.prev, img) : { found: false };
    this.prev = img;

    // Throttled model pass (don't await on the hot path beyond its own cadence).
    this.frame++;
    if (this.useModel && this.model && this.frame % this.modelEvery === 0) {
      this._runModel(video, t); // fire-and-forget; result used next frames
    }
    const model = this._lastModel && t - this._lastModel.t < 0.4 ? this._lastModel : null;

    // --- fusion ---
    const colorOK = color.found && color.area >= this.ballMinArea && color.area <= this.ballMaxArea;
    const motionOK = motion.found && motion.area <= this.motionMaxArea;

    if (colorOK) {
      let conf = 0.7, source = 'color';
      if (motionOK && dist(color, motion) < 0.18) { conf = 0.92; source = 'color+motion'; }
      else if (model && dist(color, model) < 0.18) { conf = 0.9; source = 'color+model'; }
      return { x: color.x, y: color.y, confidence: conf, source };
    }
    if (model) return { x: model.x, y: model.y, confidence: Math.min(0.85, model.confidence), source: 'model' };
    if (motionOK && motion.area >= this.ballMinArea) {
      return { x: motion.x, y: motion.y, confidence: 0.5, source: 'motion' };
    }
    return null;
  }

  reset() { this.prev = null; this._lastModel = null; this.frame = 0; }
}

export default { HybridBallDetector };
