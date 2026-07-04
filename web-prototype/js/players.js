// players.js
// ----------------------------------------------------------------------------
// PlayerRegistry — lightweight multi-person tracking + per-player scoring, so two
// (or more) people can play and each gets their own count + streak.
//
//   update(detections, t)   assign stable ids to person boxes across frames
//   attribute(point)        which player does a score event belong to (nearest)
//   recordScore(id) / recordMiss(id)   per-player count + streak bookkeeping
//
// Pure and deterministic (the caller passes timestamps) so it unit-tests in node.
// Tracking is greedy nearest-centroid with a gating distance — cheap and good
// enough for the 2-4 people who fit in a phone frame.
// ----------------------------------------------------------------------------

const NAMES = ['P1', 'P2', 'P3', 'P4', 'P5', 'P6'];

function centroid(b) { return { x: b.x + b.w / 2, y: b.y + b.h / 2 }; }
function dist2(a, b) { const dx = a.x - b.x, dy = a.y - b.y; return dx * dx + dy * dy; }

export class PlayerRegistry {
  constructor({ gateDistance = 0.18, forgetAfter = 1.5 } = {}) {
    this.gate2 = gateDistance * gateDistance; // match only within this normalized distance
    this.forgetAfter = forgetAfter;           // seconds unseen before a player is dropped
    this.reset();
  }

  reset() {
    this.players = new Map(); // id -> {id, name, box, center, lastSeen, count, streak, best, misses}
    this._nextId = 0;
    return this;
  }

  /** Assign stable ids to this frame's person boxes. Returns active players. */
  update(detections, t) {
    const dets = (detections || []).map((d) => ({ box: d.bbox || d, center: centroid(d.bbox || d) }));
    const taken = new Set();

    // Greedy match each existing player to the nearest unclaimed detection within the gate.
    for (const p of this.players.values()) {
      let best = -1, bestD = Infinity;
      dets.forEach((d, i) => {
        if (taken.has(i)) return;
        const dd = dist2(p.center, d.center);
        if (dd < bestD) { bestD = dd; best = i; }
      });
      if (best >= 0 && bestD <= this.gate2) {
        taken.add(best);
        p.box = dets[best].box; p.center = dets[best].center; p.lastSeen = t;
      }
    }

    // Unmatched detections become new players.
    dets.forEach((d, i) => {
      if (taken.has(i)) return;
      const id = this._nextId++;
      this.players.set(id, {
        id, name: NAMES[id % NAMES.length], box: d.box, center: d.center,
        lastSeen: t, count: 0, streak: 0, best: 0, misses: 0,
      });
    });

    // Forget the long-gone.
    for (const [id, p] of this.players) {
      if (t - p.lastSeen > this.forgetAfter) this.players.delete(id);
    }
    return this.active();
  }

  active() { return [...this.players.values()]; }
  get count() { return this.players.size; }

  /** Which player owns a score event at a normalized point? Nearest center, gated. */
  attribute(point) {
    let best = null, bestD = Infinity;
    for (const p of this.players.values()) {
      const dd = dist2(p.center, point);
      if (dd < bestD) { bestD = dd; best = p; }
    }
    if (!best) return null;
    // No gate on attribution distance — the closest active player owns it. (When a
    // single player plays, every make is theirs even if they roam the frame.)
    return best.id;
  }

  recordScore(id) {
    const p = this.players.get(id); if (!p) return null;
    p.count += 1; p.streak += 1; p.best = Math.max(p.best, p.streak);
    return { ...p };
  }

  recordMiss(id) {
    const p = this.players.get(id); if (!p) return null;
    p.misses += 1; p.streak = 0;
    return { ...p };
  }

  stats() {
    return this.active().map((p) => ({
      id: p.id, name: p.name, count: p.count, streak: p.streak, best: p.best, misses: p.misses,
    }));
  }
}

export default { PlayerRegistry };
