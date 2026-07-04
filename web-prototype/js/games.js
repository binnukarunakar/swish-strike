// games.js
// ----------------------------------------------------------------------------
// The Swish Strike game catalog — the single list that drives the home screen and the
// scoring sessions. This mirrors the Swift GameCatalog field-for-field, so the
// same game shows the same hero art, accent, and counting rule on both platforms.
//
// Each game carries a `ruleSpec` (a plain, serializable description of how to
// count) which `buildRule()` turns into a CountingEngine rule. Keeping the spec
// as plain data is what lets the iOS app and the web prototype share one catalog.
// ----------------------------------------------------------------------------

import { zoneCrossDownRule, zoneStreakRule, bounceReversalRule } from './countingEngine.js';

// Default zones (normalized 0..1, y down) for the zone-crossing games.
const ZONES = {
  hoop:  { left: 0.36, top: 0.26, right: 0.64, bottom: 0.38 }, // band near top-center
  goal:  { left: 0.20, top: 0.30, right: 0.80, bottom: 0.46 }, // wide goal mouth
  hole:  { left: 0.42, top: 0.40, right: 0.58, bottom: 0.52 }, // small central target
  cup:   { left: 0.44, top: 0.55, right: 0.56, bottom: 0.66 }, // putting cup, lower frame
  cups:  { left: 0.38, top: 0.42, right: 0.62, bottom: 0.56 }, // cup-pong rack, mid frame
};

/** Turn a serializable ruleSpec into a live CountingEngine rule. */
export function buildRule(spec) {
  if (spec.kind === 'zoneCrossDown') return zoneCrossDownRule(spec.zone, spec.opts || {});
  if (spec.kind === 'zoneStreak') return zoneStreakRule(spec.zone, spec.opts || {});
  if (spec.kind === 'bounceReversal') return bounceReversalRule(spec.opts || {});
  throw new Error(`unknown ruleSpec kind: ${spec.kind}`);
}

// Ordered to interleave warm/cool accents so no two same-family hues sit adjacent
// (see docs/04_DESIGN_SYSTEM.md → color science).
export const GAMES = [
  {
    slug: 'hoop-count', title: 'Hoop Count', sport: 'Basketball', heroId: 'basketball',
    accent: '#FF7A33', tag: 'Makes',
    subtitle: 'Prop your phone courtside. Every swish counts itself.',
    instructions: 'Aim the camera at the hoop, tap the rim to place the zone, then shoot. A made basket = the ball falling down through the zone.',
    flagship: true, needsTarget: true,
    ruleSpec: { kind: 'zoneCrossDown', zone: ZONES.hoop, opts: { cooldown: 0.9 } },
    doc: 'docs/games/hoop-count.md',
  },
  {
    slug: 'ping-pong-rally', title: 'Ping-Pong Rally', sport: 'Table Tennis', heroId: 'ping-pong',
    accent: '#2EC4FF', tag: 'Volleys',
    subtitle: 'Count every volley across the table.',
    instructions: 'Frame the table side-on. Each bounce-and-return is one volley. Best with bright light and a fast camera.',
    needsTarget: false,
    ruleSpec: { kind: 'bounceReversal', opts: { direction: 'bottom', minAmplitude: 0.08, cooldown: 0.18 } },
  },
  {
    slug: 'soccer-goal', title: 'Goal Scored', sport: 'Soccer', heroId: 'soccer',
    accent: '#33E07A', tag: 'Goals',
    subtitle: 'Bury it. Real goal, pop-up net, or a wall target.',
    instructions: 'Tap the four corners of the goal mouth, then shoot. A goal = the ball crossing down into the mouth.',
    needsTarget: true,
    ruleSpec: { kind: 'zoneCrossDown', zone: ZONES.goal, opts: { cooldown: 1.0, xTolerance: 0.06 } },
  },
  {
    slug: 'free-throw-streak', title: 'Free-Throw Streak', sport: 'Basketball', heroId: 'free-throw',
    accent: '#FF3B5C', tag: 'Streak',
    subtitle: 'Make them in a row. One miss resets it. Pure pressure.',
    instructions: 'Set the zone on the rim and step to the line. Sink them consecutively — the streak is the score. A miss resets it to zero.',
    needsTarget: true,
    ruleSpec: { kind: 'zoneStreak', zone: ZONES.hoop, opts: { cooldown: 1.0, missMargin: 0.18 } },
    doc: 'docs/games/free-throw-streak.md',
  },
  {
    slug: 'dribble-counter', title: 'Dribble Counter', sport: 'Basketball', heroId: 'dribble',
    accent: '#19E6C3', tag: 'Dribbles',
    subtitle: 'Crossover, between-the-legs — rack up the handles.',
    instructions: 'Frame your dribble. Each floor bounce is one dribble. Speed-dribble mode times your fastest 30 seconds.',
    needsTarget: false,
    ruleSpec: { kind: 'bounceReversal', opts: { direction: 'bottom', minAmplitude: 0.10, cooldown: 0.12 } },
  },
  {
    slug: 'cornhole', title: 'Cornhole', sport: 'Bag Toss', heroId: 'cornhole',
    accent: '#FFB52E', tag: 'In the hole',
    subtitle: 'Three-in-the-hole, automatically scored.',
    instructions: 'Tap the hole to place the target. A bag dropping into the hole zone scores 3; resting on the board scores 1.',
    needsTarget: true,
    ruleSpec: { kind: 'zoneCrossDown', zone: ZONES.hole, opts: { cooldown: 0.8, xTolerance: 0.04 } },
  },
  {
    slug: 'bottle-flip', title: 'Bottle Flip', sport: 'Trick', heroId: 'bottle-flip',
    accent: '#2E7DFF', tag: 'Sticks',
    subtitle: 'Flip it. Stick it. Count the landings.',
    instructions: 'Flip a partly-filled bottle. A clean upright landing counts. (Prototype: counts the apex of each flip; production uses orientation.)',
    needsTarget: false,
    ruleSpec: { kind: 'bounceReversal', opts: { direction: 'top', minAmplitude: 0.10, cooldown: 0.5 } },
  },
  {
    slug: 'tennis-rally', title: 'Rally Counter', sport: 'Tennis', heroId: 'tennis',
    accent: '#D4FF3D', tag: 'Shots',
    subtitle: 'Longest rally wins. Solo wall or with a partner.',
    instructions: 'Frame the court or wall. Each hit is one shot. Fast balls need a bright scene and a high-frame-rate camera.',
    needsTarget: false,
    ruleSpec: { kind: 'bounceReversal', opts: { direction: 'bottom', minAmplitude: 0.09, cooldown: 0.2 } },
  },
  {
    slug: 'catch-counter', title: 'Catch Counter', sport: 'Catch', heroId: 'catch',
    accent: '#FF4D8D', tag: 'Catches',
    subtitle: 'Play catch. Every clean catch counts; a drop ends it.',
    instructions: 'Toss and catch. Each catch at the top of the arc counts. Great for kids and warm-ups.',
    needsTarget: false,
    ruleSpec: { kind: 'bounceReversal', opts: { direction: 'top', minAmplitude: 0.12, cooldown: 0.4 } },
  },
  {
    slug: 'keepie-uppie', title: 'Keepie-Uppie', sport: 'Soccer', heroId: 'juggling',
    accent: '#C77DFF', tag: 'Touches',
    subtitle: 'Juggle it. Feet, knees, head — keep it up.',
    instructions: 'Keep the ball off the ground. Each touch (the ball bottoming out and rising again) counts. The run ends when it drops.',
    needsTarget: false,
    ruleSpec: { kind: 'bounceReversal', opts: { direction: 'bottom', minAmplitude: 0.10, cooldown: 0.22 } },
  },
  {
    slug: 'golf-putt', title: 'Golf Putt', sport: 'Golf', heroId: 'golf',
    accent: '#5BE049', tag: 'Holed',
    subtitle: 'Drain putts. The cup keeps its own tally.',
    instructions: 'Set the phone on the green behind the hole, facing your ball. A putt that rolls in = the ball dropping through the cup zone.',
    needsTarget: true,
    ruleSpec: { kind: 'zoneCrossDown', zone: ZONES.cup, opts: { cooldown: 1.5, xTolerance: 0.04 } },
  },
  {
    slug: 'cup-pong', title: 'Cup Pong', sport: 'Party', heroId: 'cup-pong',
    accent: '#FF5147', tag: 'Sinks',
    subtitle: 'House rules, auto-scored. Every sink counts.',
    instructions: 'Frame the cup rack from the side or behind. A ball dropping into the rack zone is one sink. Re-rack whenever — the count keeps going.',
    needsTarget: true,
    ruleSpec: { kind: 'zoneCrossDown', zone: ZONES.cups, opts: { cooldown: 1.0 } },
  },
  {
    slug: 'volley-bumps', title: 'Volley Bumps', sport: 'Volleyball', heroId: 'volleyball',
    accent: '#FFE03D', tag: 'Bumps',
    subtitle: 'Bump, set, repeat. How long can you keep it alive?',
    instructions: 'Frame yourself with headroom — the ball should peak inside the frame. Each bump (the ball dropping to your arms and rising) counts.',
    needsTarget: false,
    ruleSpec: { kind: 'bounceReversal', opts: { direction: 'bottom', minAmplitude: 0.11, cooldown: 0.30 } },
  },
  {
    slug: 'hacky-sack', title: 'Hacky Sack', sport: 'Footbag', heroId: 'hacky-sack',
    accent: '#8B7DFF', tag: 'Kicks',
    subtitle: 'Keep the sack off the ground. Old school.',
    instructions: 'Frame your whole body. Each kick (the sack bottoming out and popping back up) is one. The run ends when it hits the dirt.',
    needsTarget: false,
    ruleSpec: { kind: 'bounceReversal', opts: { direction: 'bottom', minAmplitude: 0.07, cooldown: 0.25 } },
  },
];

// Per-game CV metadata: what to auto-calibrate ('hoop' rim / 'board' cornhole /
// 'none'), the ball's dominant hue for color detection, and whether the player's
// body should be in frame (enables coaching + per-player scoring).
const META = {
  'hoop-count':        { calibrate: 'hoop',  ballHue: 'orange', needsBody: true },
  'free-throw-streak': { calibrate: 'hoop',  ballHue: 'orange', needsBody: true },
  'dribble-counter':   { calibrate: 'none',  ballHue: 'orange', needsBody: true },
  'cornhole':          { calibrate: 'board', ballHue: 'red',    needsBody: false },
  'soccer-goal':       { calibrate: 'none',  ballHue: 'white',  needsBody: false },
  'keepie-uppie':      { calibrate: 'none',  ballHue: 'white',  needsBody: true },
  'tennis-rally':      { calibrate: 'none',  ballHue: 'yellow', needsBody: true },
  'ping-pong-rally':   { calibrate: 'none',  ballHue: 'white',  needsBody: false },
  'catch-counter':     { calibrate: 'none',  ballHue: 'white',  needsBody: true },
  'bottle-flip':       { calibrate: 'none',  ballHue: 'blue',   needsBody: false },
  'golf-putt':         { calibrate: 'none',  ballHue: 'white',  needsBody: false },
  'cup-pong':          { calibrate: 'none',  ballHue: 'white',  needsBody: false },
  'volley-bumps':      { calibrate: 'none',  ballHue: 'yellow', needsBody: true },
  'hacky-sack':        { calibrate: 'none',  ballHue: 'red',    needsBody: true },
};
for (const g of GAMES) Object.assign(g, META[g.slug] || { calibrate: 'none', ballHue: 'orange', needsBody: false });

export function gameBySlug(slug) {
  return GAMES.find((g) => g.slug === slug) || null;
}

export default { GAMES, buildRule, gameBySlug, ZONES };
