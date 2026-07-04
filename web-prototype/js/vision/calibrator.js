// vision/calibrator.js
// ----------------------------------------------------------------------------
// Auto-calibration — find the scoring target in the live frame so the user doesn't
// have to place it by hand:
//   • hoop  — the orange rim reads as a WIDE orange blob in the upper frame.
//   • board — a cornhole board reads as a large saturated quad (blue/red/green).
// Returns the signals the coach (coach.js) needs to guide phone placement, plus a
// suggested target zone. Heuristic + cheap (reuses color.js); tap-to-place stays
// as the manual fallback. Browser-side: it takes an ImageData a caller grabs.
// ----------------------------------------------------------------------------

import { detectColorBlob, brightness, HUES } from './color.js';

/**
 * @param {{data,width,height}} img  downscaled frame
 * @param {'hoop'|'board'|'none'} mode
 * @returns {{brightness:number, targetVisible:boolean, targetBox:object|null, confidence:number}}
 */
export function analyzeFrame(img, mode) {
  const bright = brightness(img);
  if (mode === 'hoop') {
    const r = detectColorBlob(img, HUES.orange);
    if (r.found && r.bbox) {
      const b = r.bbox;
      const aspect = b.w / Math.max(b.h, 1e-3);
      const cy = b.y + b.h / 2;
      // A rim is wider than tall and sits in the upper ~70% of frame. (A ball is
      // round and roams — but during setup the ball usually isn't up there yet.)
      if (r.area > 0.004 && aspect > 1.1 && cy < 0.72) {
        // Tighten the zone to a thin band at the rim plane.
        const zone = { x: b.x, y: b.y, w: b.w, h: Math.min(b.h, 0.14) };
        return { brightness: bright, targetVisible: true, targetBox: zone, confidence: Math.min(0.9, r.area * 10 + 0.4) };
      }
    }
    return { brightness: bright, targetVisible: false, targetBox: null, confidence: 0 };
  }

  if (mode === 'board') {
    const cands = ['blue', 'red', 'green'].map((h) => detectColorBlob(img, HUES[h])).filter((c) => c.found);
    const best = cands.sort((a, b) => b.area - a.area)[0];
    if (best && best.area > 0.03 && best.bbox) {
      return { brightness: bright, targetVisible: true, targetBox: best.bbox, confidence: Math.min(0.9, best.area + 0.4) };
    }
    return { brightness: bright, targetVisible: false, targetBox: null, confidence: 0 };
  }

  // mode 'none' (bounce games) — nothing to calibrate; just report brightness.
  return { brightness: bright, targetVisible: true, targetBox: null, confidence: 1 };
}

/** Convert a detected target box into a zoneCrossDown zone {left,top,right,bottom}. */
export function boxToZone(box) {
  return { left: box.x, top: box.y, right: box.x + box.w, bottom: box.y + box.h };
}

export default { analyzeFrame, boxToZone };
