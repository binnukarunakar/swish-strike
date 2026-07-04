// vision/poseDetector.js
// ----------------------------------------------------------------------------
// PoseDetector — MoveNet MultiPose (up to 6 people) via @tensorflow-models/
// pose-detection, vendored locally. Turns the camera feed into a list of people
// (normalized bbox + a "hands" point for shot attribution + keypoints), which
// feeds the PlayerRegistry for per-player streaks. Degrades to [] if the model
// libraries aren't present, so the app never hard-depends on it.
// ----------------------------------------------------------------------------

export class PoseDetector {
  constructor({ maxPoses = 4, minScore = 0.3 } = {}) {
    this.maxPoses = maxPoses;
    this.minScore = minScore;
    this.detector = null;
    this.available = typeof window !== 'undefined' && !!window.poseDetection && !!window.tf;
  }

  async load() {
    if (!this.available) return false;
    try {
      if (window.tf.setBackend) { try { await window.tf.setBackend('webgl'); } catch {} }
      const pd = window.poseDetection;
      this.detector = await pd.createDetector(pd.SupportedModels.MoveNet, {
        modelType: pd.movenet.modelType.MULTIPOSE_LIGHTNING,
        enableTracking: true,
        trackerType: pd.TrackerType.BoundingBox,
      });
      return true;
    } catch (e) {
      console.warn('[pose] load failed:', e?.message || e);
      this.available = false; return false;
    }
  }

  /** @returns {Array<{id?,bbox:{x,y,w,h},hands:{x,y},score,keypoints}>} normalized */
  async detect(video) {
    if (!this.detector || !video || video.readyState < 2) return [];
    let poses;
    try { poses = await this.detector.estimatePoses(video, { maxPoses: this.maxPoses }); }
    catch { return []; }
    const W = video.videoWidth || 1, H = video.videoHeight || 1;
    return poses.map((p) => {
      const pts = p.keypoints.filter((k) => (k.score ?? 0) >= this.minScore);
      if (!pts.length) return null;
      let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
      for (const k of pts) { minX = Math.min(minX, k.x); maxX = Math.max(maxX, k.x); minY = Math.min(minY, k.y); maxY = Math.max(maxY, k.y); }
      // "hands" = average of wrists if present, else top-center of the box (for shot attribution).
      const byName = Object.fromEntries(p.keypoints.map((k) => [k.name, k]));
      const lw = byName.left_wrist, rw = byName.right_wrist;
      const wrists = [lw, rw].filter((w) => w && (w.score ?? 0) >= this.minScore);
      const hands = wrists.length
        ? { x: wrists.reduce((s, w) => s + w.x, 0) / wrists.length / W, y: wrists.reduce((s, w) => s + w.y, 0) / wrists.length / H }
        : { x: (minX + maxX) / 2 / W, y: minY / H };
      return {
        id: p.id,
        bbox: { x: minX / W, y: minY / H, w: (maxX - minX) / W, h: (maxY - minY) / H },
        hands,
        score: p.score ?? 0,
        keypoints: p.keypoints,
      };
    }).filter(Boolean);
  }
}

export default { PoseDetector };
