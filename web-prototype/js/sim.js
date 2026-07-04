// sim.js (v2)
// ----------------------------------------------------------------------------
// On-device simulation source. It synthesizes the WHOLE experience — a calibration
// sequence (searching → adjust → locked) and realistic play (arced basketball
// shots launched from alternating players, or a bouncing ball) — and feeds it
// through the exact same coach / detector / tracker / engine / player pipeline the
// camera uses. This is why the app is runnable with zero network/model and why
// the full flow is testable headlessly: same clock in → same result out.
// ----------------------------------------------------------------------------

function zoneToBox(z) { return { x: z.left, y: z.top, w: z.right - z.left, h: z.bottom - z.top }; }

export function makeSimSource(game) {
  const mode = game.calibrate || 'none';
  const isHoop = mode === 'hoop';            // basketball rim games get swish/rattle variety
  const spec = game.ruleSpec;
  const isStreak = spec.kind === 'zoneStreak'; // free-throw: shots that can miss
  const isZone = spec.kind === 'zoneCrossDown' || isStreak;
  const zone = isZone ? spec.zone : null;
  const hoopCx = isZone ? (zone.left + zone.right) / 2 : 0.5;
  // The sim ball must clearly clear the zone's bottom edge or low targets
  // (putting cup, cup rack) would never register a score.
  const fallEnd = isZone ? Math.min(0.95, zone.bottom + 0.18) : 0.60;

  // two players for zone games (left/right), one centered player for bounce games
  const twoPlayers = [
    { bbox: { x: 0.24, y: 0.45, w: 0.14, h: 0.50 } }, // P1 ~ center 0.31
    { bbox: { x: 0.62, y: 0.45, w: 0.14, h: 0.50 } }, // P2 ~ center 0.69
  ];
  const onePlayer = [{ bbox: { x: 0.42, y: 0.34, w: 0.16, h: 0.60 } }];

  // Free-throw streak: one shooter at the line. Most shots drop clean; every
  // fourth bricks out wide (a miss the engine must reset the streak on), and some
  // makes rattle in off the rim. The trajectory is deliberately robust at ANY
  // sampling rate (headless rAF can run coarse/irregular): the ball hovers at the
  // apex IN BAND long enough that some sample always arms the attempt, and a
  // brick's entire fall happens far outside the band — so a lagging EMA can never
  // read a miss as a make, no matter how few frames sample the flight.
  function playFreeThrow(t) {
    const P = 2.4;
    const cycle = Math.floor(t / P);
    const phase = (t % P) / P;
    const willMiss = cycle % 4 === 3;
    const rattle = !willMiss && cycle % 3 === 2;
    const sx = 0.5, apexY = 0.08; // free-throw line, centered; apex above the rim
    if (phase < 0.10) return { ball: { x: sx, y: 0.84, confidence: 0.9 }, players: onePlayer, launch: { x: sx, y: 0.84 } };
    if (phase < 0.42) { // rise, centered — the top of the rise is already in-band above the rim
      const k = (phase - 0.10) / 0.32;
      return { ball: { x: sx, y: 0.84 + (apexY - 0.84) * k, confidence: 0.9 }, players: onePlayer, launch: null };
    }
    if (phase < 0.52) { // hover at the apex, centered — guarantees arming at any fps
      return { ball: { x: sx, y: apexY, confidence: 0.95 }, players: onePlayer, launch: null };
    }
    if (willMiss) {
      if (phase < 0.62) { // slide wide while still high — leaves the band before falling
        const k = (phase - 0.52) / 0.10;
        return { ball: { x: sx + 0.40 * k, y: apexY + 0.04 * k, confidence: 0.95 }, players: onePlayer, launch: null };
      }
      if (phase < 0.88) { // the WHOLE fall happens at x=0.90, far outside the band
        const k = (phase - 0.62) / 0.26;
        return { ball: { x: 0.90, y: 0.12 + (0.95 - 0.12) * k, confidence: 0.95 }, players: onePlayer, launch: null };
      }
      return { ball: null, players: onePlayer, launch: null };
    }
    if (phase < 0.88) { // make: fall through the rim (a rattle drifts onto the iron)
      const k = (phase - 0.52) / 0.36;
      const x = rattle ? hoopCx + 0.12 * Math.min(1, k / 0.35) : hoopCx;
      return { ball: { x, y: apexY + (fallEnd - apexY) * k, confidence: 0.95 }, players: onePlayer, launch: null };
    }
    return { ball: null, players: onePlayer, launch: null };
  }

  return {
    label: isZone ? 'arced shots from two players' : 'a ball bouncing in rhythm',

    // Coach signals for the SETUP phase: searching → adjust (too small) → locked.
    calibration(t) {
      const bodyVisible = t > 0.8;
      const brightness = 0.5;
      if (mode === 'none') {
        const targetBox = t > 0.6 ? { x: 0.30, y: 0.30, w: 0.40, h: 0.30 } : null;
        return { targetVisible: !!targetBox, targetBox, brightness, bodyVisible };
      }
      const box = zoneToBox(zone || { left: 0.4, top: 0.4, right: 0.6, bottom: 0.55 });
      if (t < 0.7) return { targetVisible: false, targetBox: null, brightness, bodyVisible };
      if (t < 1.6) { // found but framed too small -> coach says "move closer"
        return { targetVisible: true, targetBox: { x: box.x + box.w * 0.25, y: box.y, w: box.w * 0.5, h: box.h * 0.5 }, brightness, bodyVisible };
      }
      return { targetVisible: true, targetBox: box, brightness, bodyVisible }; // locked
    },

    // PLAY phase: returns { ball, players, launch } at simulated time t.
    play(t) {
      if (isStreak) return playFreeThrow(t);
      if (!isZone) {
        const period = 0.62, amp = 0.27;
        const y = 0.5 + amp * Math.cos((t / period) * Math.PI * 2);
        return {
          ball: { x: 0.5 + Math.sin(t * 1.7) * 0.05, y, confidence: 0.95 },
          players: onePlayer, launch: null,
        };
      }
      const P = 2.2;                          // seconds per shot
      const cycle = Math.floor(t / P);
      const phase = (t % P) / P;
      const active = cycle % 2;               // alternate shooters
      const px = active ? 0.69 : 0.31;        // launch column = that player
      // Basketball only: every third make rattles in off the rim instead of a
      // clean swish, so the differentiated feedback is visible in the demo. The
      // ball still drops through the zone, so the COUNT is unchanged either way.
      const rattle = isHoop && (cycle % 3 === 2);
      let ball = null;
      let launch = null;
      if (phase < 0.12) {                     // ball in hands, low, by the shooter
        ball = { x: px, y: 0.82, confidence: 0.9 };
        launch = { x: px, y: 0.82 };
      } else if (phase < 0.5) {               // rise: shooter -> apex above the hoop
        const k = (phase - 0.12) / 0.38;
        ball = { x: px + (hoopCx - px) * k, y: 0.82 + (0.10 - 0.82) * k, confidence: 0.9 };
      } else if (phase < 0.82) {              // fall: apex -> down through the target
        const k = (phase - 0.5) / 0.32;
        // A rattle reaches the rim edge early and holds (off-center cross → the
        // engine reads it as a rim make); a swish falls straight through center.
        // Reaching the edge before the crossing lets the EMA settle there.
        const fx = rattle ? hoopCx + 0.12 * Math.min(1, k / 0.35) : hoopCx;
        ball = { x: fx, y: 0.10 + (fallEnd - 0.10) * k, confidence: 0.95 };
      } // else: ball gone, engine re-arms for the next shot
      return { ball, players: twoPlayers, launch };
    },
  };
}

export default { makeSimSource };
