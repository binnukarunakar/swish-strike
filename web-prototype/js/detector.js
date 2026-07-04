// detector.js
// ----------------------------------------------------------------------------
// COCO-SSD wrapper for the live-camera source. Loads the model once, runs it on
// a <video> frame, keeps only the 'sports ball' class, picks one box, and
// converts COCO's pixel box to a normalized TOP-LEFT center {x,y,confidence} so
// coordinates match the engine + the iOS BallDetector convention.
//
// The model libraries (tf + coco-ssd) are expected as globals loaded by
// index.html from the locally vendored bundles. If they aren't present, the
// detector reports unavailable and the UI falls back to the simulation source —
// the prototype never hard-depends on a network model download.
// ----------------------------------------------------------------------------

export class BallDetector {
  constructor() {
    this.model = null;
    this.available = typeof window !== 'undefined'
      && typeof window.cocoSsd !== 'undefined'
      && typeof window.tf !== 'undefined';
  }

  /** Load the model once. Resolves false if unavailable (no globals). */
  async load() {
    if (!this.available) return false;
    if (this.model) return true;
    try {
      // Prefer WebGL backend for speed; fall back silently to CPU.
      if (window.tf?.setBackend) { try { await window.tf.setBackend('webgl'); } catch { /* cpu */ } }
      this.model = await window.cocoSsd.load({ base: 'lite_mobilenet_v2' });
      return true;
    } catch (err) {
      console.warn('[detector] model load failed, will use simulation:', err?.message || err);
      this.available = false;
      return false;
    }
  }

  /**
   * Detect the best ball in a video frame. Returns {x,y,confidence} normalized
   * top-left, or a {confidence:0} miss frame if no ball is found.
   * @param {HTMLVideoElement} video
   * @param {{x:number,y:number}|null} prev  previous normalized point (for nearest-track selection)
   */
  async detect(video, prev) {
    if (!this.model) return { x: 0.5, y: 0.5, confidence: 0 };
    const w = video.videoWidth || 1, h = video.videoHeight || 1;
    let preds;
    try { preds = await this.model.detect(video, 5); }
    catch { return { x: 0.5, y: 0.5, confidence: 0 }; }

    const balls = preds.filter((p) => p.class === 'sports ball');
    if (balls.length === 0) return { x: 0.5, y: 0.5, confidence: 0 };

    // Convert to normalized centers (top-left origin).
    const cands = balls.map((b) => ({
      x: (b.bbox[0] + b.bbox[2] / 2) / w,
      y: (b.bbox[1] + b.bbox[3] / 2) / h,
      confidence: b.score,
    }));

    // Selection: nearest to previous track, else highest confidence.
    let best;
    if (prev) {
      best = cands.reduce((a, c) => {
        const da = (a.x - prev.x) ** 2 + (a.y - prev.y) ** 2;
        const dc = (c.x - prev.x) ** 2 + (c.y - prev.y) ** 2;
        return dc < da ? c : a;
      });
    } else {
      best = cands.reduce((a, c) => (c.confidence > a.confidence ? c : a));
    }
    // The <video> is mirrored in CSS (scaleX(-1)); mirror x so the overlay lines up.
    return { x: 1 - best.x, y: best.y, confidence: best.confidence };
  }
}

export default { BallDetector };
