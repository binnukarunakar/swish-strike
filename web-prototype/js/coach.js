// coach.js
// ----------------------------------------------------------------------------
// The camera coach. Given cheap per-frame signals (is the target in frame? how
// big? where? how bright? is the player's full body visible?), it returns concrete
// guidance to position the phone — "step back", "tilt up", "too dark", "locked in".
// Pure functions so the heuristics unit-test in node; the vision layer feeds it
// real signals, the simulation feeds it synthetic ones.
// ----------------------------------------------------------------------------

/**
 * @param {object} s signals:
 *   targetVisible: boolean        — was the hoop/board found?
 *   targetBox: {x,y,w,h}|null     — normalized box of the target (if found)
 *   brightness: number            — 0..1 mean luminance
 *   needsBody: boolean            — does this game need the player's body in frame?
 *   bodyVisible: boolean          — is at least one full body visible?
 * @param {object} cfg thresholds
 * @returns {{ready:boolean, status:'searching'|'adjust'|'ready', primary:string, hints:string[], target:object|null}}
 */
export function coach(s, cfg = {}) {
  const minTargetArea = cfg.minTargetArea ?? 0.012;  // target should fill >~1.2% of frame
  const maxTargetArea = cfg.maxTargetArea ?? 0.30;   // ...but not dominate it
  const edgeMargin = cfg.edgeMargin ?? 0.04;         // keep the target off the frame edge
  const minBrightness = cfg.minBrightness ?? 0.18;
  const hints = [];

  if (s.brightness != null && s.brightness < minBrightness) {
    hints.push('Too dark — add light or move somewhere brighter');
  }

  if (!s.targetVisible || !s.targetBox) {
    return {
      ready: false, status: 'searching',
      primary: 'Point the camera at the target',
      hints: hints.length ? hints : ['Scanning for the hoop…'],
      target: null,
    };
  }

  const b = s.targetBox;
  const area = b.w * b.h;
  const cx = b.x + b.w / 2, cy = b.y + b.h / 2;

  if (area < minTargetArea) hints.push('Move closer — the target looks small');
  else if (area > maxTargetArea) hints.push('Step back — the target fills the frame');

  if (b.y < edgeMargin) hints.push('Tilt down a little');
  else if (b.y + b.h > 1 - edgeMargin) hints.push('Tilt up a little');
  if (cx < 0.2) hints.push('Pan right to center the target');
  else if (cx > 0.8) hints.push('Pan left to center the target');

  if (s.needsBody && !s.bodyVisible) hints.push('Step back so I can see your whole body');

  if (hints.length === 0) {
    return {
      ready: true, status: 'ready',
      primary: 'Locked in — start shooting',
      hints: [], target: { cx, cy, area },
    };
  }
  return {
    ready: false, status: 'adjust',
    primary: hints[0],
    hints, target: { cx, cy, area },
  };
}

export default { coach };
