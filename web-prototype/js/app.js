// app.js (v2) — the orchestrator + state machine.
// Home → Setup (coach + auto-calibrate) → Play (live HUD, per-player) → Result.
// Wires the simulation OR the real camera-vision pipeline through one path:
//   frame → (coach during setup) → detector → tracker → engine → players → UI.
// The only module that touches the DOM/camera.

import { GAMES, gameBySlug, buildRule } from './games.js';
import { heroSVG } from './heroArt.js';
import { CountingEngine } from './countingEngine.js';
import { BallTracker } from './tracker.js';
import { PlayerRegistry } from './players.js';
import { coach } from './coach.js';
import { makeSimSource } from './sim.js';
import { TrailBuffer, Heat } from './playfx.js';
import { Sfx } from './sfx.js';
import { HybridBallDetector } from './vision/ballDetector.js';
import { PoseDetector } from './vision/poseDetector.js';
import { analyzeFrame, boxToZone } from './vision/calibrator.js';

const $ = (s) => document.querySelector(s);
const clamp01 = (v) => Math.min(1, Math.max(0, v));
const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
// Zone-target games (a placed target the ball falls through): plain count or streak.
const isZoneGame = (spec) => !!spec && (spec.kind === 'zoneCrossDown' || spec.kind === 'zoneStreak');

const FLAVOR = {
  'hoop-count': ['Swish!', 'Bucket!', 'Cash!', 'Splash!'],
  'free-throw-streak': ['Money.', 'Ice cold.', 'Nothing but net.'],
  'soccer-goal': ['GOAL!', 'Top bins!', 'Back of the net!'],
  'cornhole': ['In the hole!', 'Drilled it.', 'Four-bagger!'],
  'keepie-uppie': ['Keep it up!', 'Silky.', 'Touch!'],
  'dribble-counter': ['Handles.', 'Tight.', 'Bounce.'],
  'ping-pong-rally': ['Rally!', 'Tick-tock.', 'Volley!'],
  'tennis-rally': ['Rally!', 'Clean strike.', 'Again!'],
  'catch-counter': ['Caught it!', 'Nice hands.', 'Snagged.'],
  'bottle-flip': ['Stuck it!', 'Landed!', 'Clean flip.'],
  'golf-putt': ['Drained it.', 'Center cup.', 'Pure roll.'],
  'cup-pong': ['Sunk it!', 'Splash.', 'Rack em up.'],
  'volley-bumps': ['Bump!', 'Clean platform.', 'Keep it alive!'],
  'hacky-sack': ['Kick!', 'Stalled it.', 'Old school.'],
};

// Basketball reads the shot quality off the engine event and calls it differently:
// a clean swish vs a make that rattles in off the rim. Both still count.
const QUALITY_FLAVOR = {
  swish: ['Swish!', 'Nothing but net.', 'Cash!', 'Splash!'],
  rim: ['Rattles in!', 'Shooter’s roll.', 'Off the iron — counts.', 'Friendly bounce.'],
};

// Inline UI icons — emoji render inconsistently across platforms (and are banned by
// the project UI rules), so the voice toggle, streak flame, and leader crown use
// crafted SVG. `currentColor` lets each inherit its surrounding text color.
const ICONS = {
  speakerOn: `<svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true"><path d="M4 9v6h4l5 4V5L8 9H4z" fill="currentColor"/><path d="M15.5 8.5a4.5 4.5 0 0 1 0 7" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>`,
  speakerOff: `<svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true"><path d="M4 9v6h4l5 4V5L8 9H4z" fill="currentColor"/><path d="M16 9l5 6M21 9l-5 6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>`,
  flame: `<svg viewBox="0 0 24 24" width="12" height="12" aria-hidden="true"><path d="M12 2c1 3-2 4-2 7a2 2 0 0 0 4 0c0-1 .2-1.4.5-2C16 10 18 12 18 15a6 6 0 0 1-12 0C6 11 9 9 12 2z" fill="currentColor"/></svg>`,
  crown: `<svg viewBox="0 0 24 24" width="14" height="14" aria-hidden="true"><path d="M3 7l4 4 5-7 5 7 4-4-1.6 11H4.6L3 7z" fill="currentColor"/></svg>`,
};

// Voice callouts — on-device TTS (speechSynthesis), no network. Speaks the new
// count on every score; flavor toasts stay on screen. Persisted mute toggle.
const Voice = {
  on: localStorage.getItem('swishstrike.voice') !== 'off',
  toggle() {
    this.on = !this.on;
    localStorage.setItem('swishstrike.voice', this.on ? 'on' : 'off');
    if (!this.on) try { speechSynthesis.cancel(); } catch {}
    return this.on;
  },
  say(text) {
    if (!this.on || typeof speechSynthesis === 'undefined') return;
    try {
      speechSynthesis.cancel(); // a new score interrupts the previous callout
      const u = new SpeechSynthesisUtterance(text);
      u.rate = 1.15; u.pitch = 1.0; u.volume = 0.9;
      speechSynthesis.speak(u);
    } catch { /* TTS unavailable — silent */ }
  },
};

// Synthesized game sounds (no audio files). One speaker button mutes everything,
// so SFX is kept in lockstep with the Voice toggle (see init()).
const sfx = new Sfx();
sfx.muted = !Voice.on;

const S = {
  screen: 'home', phase: 'setup', game: null, source: 'sim',
  engine: null, tracker: null, registry: null, sim: null,
  detector: null, pose: null, activeZone: null,
  video: null, canvas: null, ctx: null, grabCanvas: null, grabCtx: null,
  running: false, t0: 0, phaseT0: 0, readyFrames: 0, raf: 0,
  lastLow: null, lastBall: null, coachState: null, peopleThrottle: 0, lastPeople: [],
  trail: null, heat: null, streak: 0, savedArc: null, // play-phase effects (playfx.js)
  startBest: 0, pbCelebrated: false, wasOnFire: false, // PB + on-fire sound triggers
  maxStreak: 0, // longest streak this run (streak games headline this, not the current count)
};

// ---------------- Home ----------------
function bestFor(slug) { return Number(localStorage.getItem(`swishstrike.best.${slug}`) || 0); }
function setBest(slug, n) { if (n > bestFor(slug)) localStorage.setItem(`swishstrike.best.${slug}`, String(n)); }

function renderHome() {
  const grid = $('#grid'); grid.innerHTML = '';
  for (const g of GAMES) {
    const best = bestFor(g.slug);
    const card = document.createElement('div');
    card.className = 'card'; card.dataset.testid = `card-${g.slug}`;
    card.style.boxShadow = `0 0 26px -8px ${g.accent}55`;
    card.innerHTML = `
      <div class="hero">${heroSVG(g.heroId)}</div>
      ${g.flagship ? '<div class="flag">Flagship</div>' : ''}
      ${best > 0 ? `<div class="best">PB ${best}</div>` : ''}
      <div class="meta"><div class="title">${g.title}</div>
        <div class="tag" style="color:${g.accent}">${g.sport} · ${g.tag}</div></div>`;
    card.addEventListener('click', () => openGame(g.slug));
    grid.appendChild(card);
  }
}

// ---------------- Open a game ----------------
async function openGame(slug) {
  const g = gameBySlug(slug); if (!g) return;
  sfx.unlock(); // opening a game is a user gesture — unlock audio here
  S.game = g;
  document.documentElement.style.setProperty('--accent', g.accent);
  $('#game-name').textContent = g.title;
  S.activeZone = g.ruleSpec.zone ? { ...g.ruleSpec.zone } : null;
  S.engine = new CountingEngine(buildRule(g.ruleSpec));
  S.tracker = new BallTracker();
  S.registry = new PlayerRegistry();
  S.trail = new TrailBuffer();
  S.heat = new Heat();
  S.streak = 0; S.savedArc = null;
  S.lastLow = null; S.lastBall = null; S.lastPeople = [];
  // The sim is per-GAME state, not per-loop: if a game is opened while the loop
  // is already running (game-to-game switch), startLoop early-returns and would
  // otherwise leave the previous game's simulation feeding this game's engine.
  S.sim = makeSimSource(g);
  ensureStage();
  showScreen('game');
  enterSetup();
  if (S.source === 'cam') await startCamera();
  startLoop();
}

function showScreen(name) {
  S.screen = name;
  $('#home').classList.toggle('active', name === 'home');
  $('#game').classList.toggle('active', name === 'game');
}

function setPhase(p) {
  S.phase = p; S.phaseT0 = performance.now();
  $('#game').dataset.phase = p;
}

// ---------------- Setup / coaching ----------------
function enterSetup() {
  setPhase('setup');
  S.readyFrames = 0;
  $('#coach-msg').textContent = S.source === 'cam' ? 'Starting camera…' : 'Scanning…';
  $('#coach-hints').innerHTML = '';
  $('#setup-start').disabled = true;
  $('#setup-start').classList.remove('ready');
}

function setupSignals(tPhase) {
  if (S.source === 'sim') return S.sim.calibration(tPhase);
  // camera: analyze a downscaled frame
  const img = grab();
  if (!img) return { targetVisible: false, targetBox: null, brightness: 0.5, bodyVisible: false };
  const a = analyzeFrame(img, S.game.calibrate);
  const bodyVisible = S.lastPeople.length > 0;
  return { targetVisible: a.targetVisible, targetBox: a.targetBox, brightness: a.brightness, bodyVisible };
}

function setupTick(tPhase) {
  const sig = setupSignals(tPhase);
  const c = coach({ ...sig, needsBody: S.game.needsBody });
  S.coachState = { ...c, target: sig.targetBox };
  $('#coach-msg').textContent = c.primary;
  $('#coach-hints').innerHTML = c.hints.map((h) => `<li>${h}</li>`).join('');
  drawSetupOverlay(sig.targetBox, c.status);

  if (c.ready) {
    S.readyFrames++;
    const need = S.source === 'sim' ? 18 : 12; // ~0.3-0.6s of stable "ready"
    $('#setup-start').disabled = false;
    $('#setup-start').classList.add('ready');
    if (S.readyFrames >= need) {
      if (sig.targetBox && isZoneGame(S.game.ruleSpec)) {
        S.activeZone = boxToZone(sig.targetBox);
      }
      enterPlay();
    }
  } else {
    S.readyFrames = 0;
    $('#setup-start').disabled = true;
    $('#setup-start').classList.remove('ready');
  }
}

// ---------------- Play ----------------
function enterPlay() {
  setPhase('play');
  $('#count-label').textContent = S.game.tag;
  S.engine = new CountingEngine(currentRule());
  S.tracker.reset();
  S.registry.reset();
  S.trail.clear();
  S.heat.reset();
  S.streak = 0; S.savedArc = null;
  S.startBest = bestFor(S.game.slug); // PB to beat this run
  S.pbCelebrated = false; S.wasOnFire = false; S.maxStreak = 0;
  S.lastLow = null;
  updateCount(0);
  renderPlayers();
}

function currentRule() {
  const spec = S.game.ruleSpec;
  if (isZoneGame(spec) && S.activeZone) return buildRule({ ...spec, zone: S.activeZone });
  return buildRule(spec);
}

async function playFrame(t) {
  let ball = null, peopleBoxes = [];
  if (S.source === 'sim') {
    const r = S.sim.play(t);
    ball = r.ball; peopleBoxes = r.players || [];
  } else {
    ball = await S.detector.detect(S.video, t);
    if (S.pose && (S.peopleThrottle++ % 3 === 0)) S.lastPeople = await S.pose.detect(S.video);
    peopleBoxes = S.lastPeople;
  }
  S.registry.update(peopleBoxes, t);

  const tracked = S.tracker.update(ball ? { t, x: ball.x, y: ball.y } : null, t);
  const valid = tracked && tracked.valid;
  const conf = valid && !tracked.coasting ? (ball?.confidence ?? 0.8) : (valid ? 0.5 : 0);
  if (valid) {
    S.lastBall = { x: tracked.x, y: tracked.y };
    S.trail.push(performance.now(), tracked.x, tracked.y); // comet trail
    if (tracked.y > 0.7) S.lastLow = { x: tracked.x, y: tracked.y }; // remember the launch zone
  }
  S.heat.tick(t); // decay the streak-heat meter every frame
  if (!S.heat.onFire) S.wasOnFire = false; // re-arm the on-fire chime once it cools
  const fired = S.engine.update({ t, x: tracked?.x, y: tracked?.y, confidence: conf });
  if (fired) onScore();
  else if (S.engine.justMissed) onMiss();

  updateCount(S.engine.count);
  drawPlayOverlay();
  renderPlayers();
}

function onScore() {
  const point = S.lastLow || S.lastBall || { x: 0.5, y: 0.5 };
  const pid = S.registry.count ? S.registry.attribute(point) : null;
  let who = null;
  if (pid != null) who = S.registry.recordScore(pid);

  const quality = S.engine.lastEvent?.quality || null; // 'swish' | 'rim' | null (non-zone games)
  const flavors = quality ? QUALITY_FLAVOR[quality] : (FLAVOR[S.game.slug] || ['Score!']);
  const f = flavors[(S.engine.count - 1) % flavors.length];
  toast(who ? `${who.name}: ${f}  ·  ${who.count}` : `${f}  ·  ${S.engine.count}`);
  Voice.say(who ? `${who.name}, ${who.count}` : String(S.engine.count));

  S.streak += 1;
  S.heat.bump();
  S.maxStreak = Math.max(S.maxStreak, S.engine.count); // longest streak this run
  S.savedArc = S.trail.snapshotArc(performance.now()); // freeze the made-shot arc for replay + share

  // sound: rim rattle vs clean swish vs a generic pop for non-basketball games
  if (quality === 'rim') sfx.rim();
  else if (quality === 'swish') sfx.swish();
  else sfx.pop();
  if (S.heat.onFire && !S.wasOnFire) { sfx.streak(); S.wasOnFire = true; } // first time on fire
  if (!S.pbCelebrated && S.startBest > 0 && S.engine.count > S.startBest) {
    S.pbCelebrated = true; sfx.pb(); toast(`New best — ${S.engine.count}`);
  }

  pulse(quality);
  // differentiated haptics: a clean swish is one crisp tap; a rim make stutters
  if (navigator.vibrate) navigator.vibrate(quality === 'rim' ? [10, 35, 14] : 22);
  setBest(S.game.slug, S.engine.count);
}

// Streak games only: the ball was aimed at the rim but fell past it — streak broken.
function onMiss() {
  toast('Streak broken');
  Voice.say('Missed');
  sfx.miss();
  if (S.heat) S.heat.reset(); // cool the screen — the run is over
  S.wasOnFire = false;
  missFlash();
  if (navigator.vibrate) navigator.vibrate([28, 40, 28]);
}

function renderPlayers() {
  const el = $('#players'); if (!el) return;
  const stats = S.registry ? S.registry.stats() : [];
  if (stats.length <= 1) { el.innerHTML = ''; el.classList.remove('show'); return; }
  el.classList.add('show');
  el.innerHTML = stats.map((p) => `
    <div class="pchip">
      <span class="pname">${p.name}</span>
      <span class="pcount">${p.count}</span>
      ${p.streak >= 2 ? `<span class="pfire">${ICONS.flame}${p.streak}</span>` : ''}
    </div>`).join('');
}

// ---------------- Result ----------------
function finishGame() {
  setPhase('result');
  const stats = S.registry ? S.registry.stats() : [];
  const isStreak = S.game.ruleSpec.kind === 'zoneStreak';
  const total = isStreak ? S.maxStreak : S.engine.count; // streak games headline the longest run
  $('#result-total').textContent = total;
  $('#result-game').textContent = isStreak ? `${S.game.title} · longest streak` : `${S.game.title} · ${S.game.tag}`;

  // shot-quality breakdown (basketball) + new-personal-best badge
  const evs = S.engine.events || [];
  const swishes = evs.filter((e) => e.quality === 'swish').length;
  const rims = evs.filter((e) => e.quality === 'rim').length;
  const bd = $('#result-breakdown');
  const hasQuality = swishes + rims > 0;
  bd.textContent = hasQuality ? `${swishes} swish · ${rims} off the rim` : '';
  bd.style.display = hasQuality ? 'block' : 'none';
  const pbEl = $('#result-pb');
  const newPB = S.startBest > 0 && total > S.startBest;
  pbEl.style.display = newPB ? 'block' : 'none';

  const list = $('#result-players');
  if (stats.length > 1) {
    list.innerHTML = stats.sort((a, b) => b.count - a.count)
      .map((p, i) => `<div class="prow ${i === 0 ? 'lead' : ''}"><span>${i === 0 ? `<span class="crown">${ICONS.crown}</span> ` : ''}${p.name}</span><b>${p.count}</b><small>best streak ${p.best}</small></div>`).join('');
    list.classList.add('show');
  } else {
    list.innerHTML = ''; list.classList.remove('show');
  }
  drawShareCard(total, stats);
}

// ---------------- Render: overlays ----------------
function ensureStage() {
  S.video = $('#video'); S.canvas = $('#overlay');
  const r = S.canvas.getBoundingClientRect();
  S.canvas.width = Math.max(360, Math.round(r.width));
  S.canvas.height = Math.max(480, Math.round(r.height));
  S.ctx = S.canvas.getContext('2d');
  if (!S.grabCanvas) { S.grabCanvas = document.createElement('canvas'); S.grabCtx = S.grabCanvas.getContext('2d', { willReadFrequently: true }); }
}
function grab() {
  if (!S.video || S.video.readyState < 2) return null;
  const vw = S.video.videoWidth || 320, vh = S.video.videoHeight || 240;
  const w = 160, h = Math.round((vh / vw) * 160);
  S.grabCanvas.width = w; S.grabCanvas.height = h;
  S.grabCtx.drawImage(S.video, 0, 0, w, h);
  return S.grabCtx.getImageData(0, 0, w, h);
}

function drawSetupOverlay(box, status) {
  const ctx = S.ctx, W = S.canvas.width, H = S.canvas.height;
  ctx.clearRect(0, 0, W, H);
  const accent = S.game.accent;
  const col = status === 'ready' ? '#33E07A' : status === 'adjust' ? '#FFB52E' : accent;
  if (!box) { // scanning sweep
    const t = (performance.now() / 1000) % 1.4;
    ctx.strokeStyle = accent + '55'; ctx.lineWidth = 2;
    ctx.beginPath(); ctx.moveTo(0, t * H); ctx.lineTo(W, t * H); ctx.stroke();
    return;
  }
  const x = box.x * W, y = box.y * H, w = box.w * W, h = box.h * H;
  ctx.save();
  ctx.strokeStyle = col; ctx.lineWidth = 3; ctx.setLineDash([10, 8]);
  ctx.lineDashOffset = -(performance.now() / 30) % 18;
  roundRect(ctx, x, y, w, h, 10); ctx.stroke();
  // corner brackets
  ctx.setLineDash([]); ctx.lineWidth = 4;
  bracket(ctx, x, y, 18, 1, 1); bracket(ctx, x + w, y, 18, -1, 1);
  bracket(ctx, x, y + h, 18, 1, -1); bracket(ctx, x + w, y + h, 18, -1, -1);
  if (status === 'ready') { ctx.fillStyle = '#33E07A22'; roundRect(ctx, x, y, w, h, 10); ctx.fill(); }
  ctx.restore();
}

function drawPlayOverlay() {
  const ctx = S.ctx, W = S.canvas.width, H = S.canvas.height;
  ctx.clearRect(0, 0, W, H);
  const accent = S.game.accent;
  // streak heat — the screen edges warm up as you score in rhythm
  const heat = S.heat ? S.heat.level : 0;
  if (heat > 0.02) {
    const g = ctx.createRadialGradient(W / 2, H / 2, Math.min(W, H) * 0.34, W / 2, H / 2, Math.max(W, H) * 0.66);
    g.addColorStop(0, 'rgba(0,0,0,0)');
    g.addColorStop(1, `rgba(255,90,31,${(0.40 * heat).toFixed(3)})`);
    ctx.save(); ctx.fillStyle = g; ctx.fillRect(0, 0, W, H); ctx.restore();
  }
  // locked zone
  if (isZoneGame(S.game.ruleSpec) && S.activeZone) {
    const z = S.activeZone;
    ctx.save();
    ctx.strokeStyle = accent; ctx.lineWidth = 2.5; ctx.setLineDash([9, 7]); ctx.globalAlpha = 0.9;
    ctx.strokeRect(z.left * W, z.top * H, (z.right - z.left) * W, (z.bottom - z.top) * H);
    ctx.restore();
  }
  // player boxes (multiplayer)
  const stats = S.registry.active();
  if (stats.length > 1) {
    ctx.save(); ctx.lineWidth = 2; ctx.font = '12px -apple-system, sans-serif';
    for (const p of stats) {
      const b = p.box;
      ctx.strokeStyle = '#ffffff55';
      ctx.strokeRect(b.x * W, b.y * H, b.w * W, b.h * H);
      ctx.fillStyle = accent; ctx.fillText(`${p.name} · ${p.count}`, b.x * W + 4, b.y * H - 6);
    }
    ctx.restore();
  }
  // comet trail — a fading streak tracing the ball's recent path
  if (S.trail) {
    const pts = S.trail.live(performance.now());
    for (let i = 1; i < pts.length; i++) {
      const a = pts[i - 1], b = pts[i];
      ctx.save();
      ctx.lineCap = 'round'; ctx.strokeStyle = accent;
      ctx.globalAlpha = b.fade * 0.7; ctx.lineWidth = 2 + b.fade * 7;
      ctx.beginPath(); ctx.moveTo(a.x * W, a.y * H); ctx.lineTo(b.x * W, b.y * H); ctx.stroke();
      ctx.restore();
    }
  }
  // ball marker
  if (S.lastBall) {
    const x = S.lastBall.x * W, y = S.lastBall.y * H;
    ctx.save();
    const g = ctx.createRadialGradient(x, y, 2, x, y, 24);
    g.addColorStop(0, accent); g.addColorStop(1, accent + '00');
    ctx.fillStyle = g; ctx.beginPath(); ctx.arc(x, y, 24, 0, 7); ctx.fill();
    ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.arc(x, y, 6, 0, 7); ctx.fill();
    ctx.restore();
  }
  // on-fire badge — drawn on the canvas (no DOM, no emoji)
  if (S.heat && S.heat.onFire) {
    ctx.save();
    ctx.globalAlpha = reduceMotion ? 0.85 : 0.7 + 0.3 * Math.sin(performance.now() / 110);
    ctx.fillStyle = '#FFB52E'; ctx.textAlign = 'center';
    ctx.font = '800 13px -apple-system, system-ui, sans-serif';
    ctx.fillText('ON FIRE', W / 2, H * 0.30);
    ctx.restore();
  }
}

function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r); ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
}
function bracket(ctx, x, y, s, dx, dy) {
  ctx.beginPath(); ctx.moveTo(x, y + dy * s); ctx.lineTo(x, y); ctx.lineTo(x + dx * s, y); ctx.stroke();
}
// A small filled crown for the share-card leader (replaces the trophy emoji).
function drawCrown(ctx, x, y, color) {
  ctx.save();
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.moveTo(x, y + 14); ctx.lineTo(x + 3, y);
  ctx.lineTo(x + 9, y + 8); ctx.lineTo(x + 15, y - 3);
  ctx.lineTo(x + 21, y + 8); ctx.lineTo(x + 27, y);
  ctx.lineTo(x + 30, y + 14); ctx.closePath();
  ctx.fill();
  ctx.restore();
}

function drawShareCard(total, stats) {
  const cv = $('#share-card'); if (!cv) return;
  const ctx = cv.getContext('2d'); const W = cv.width = 540, H = cv.height = 720;
  const accent = S.game.accent;
  const grad = ctx.createLinearGradient(0, 0, 0, H);
  grad.addColorStop(0, '#0A0B0E'); grad.addColorStop(1, '#15171C');
  ctx.fillStyle = grad; ctx.fillRect(0, 0, W, H);

  ctx.textAlign = 'center';
  ctx.fillStyle = '#F4F6FA'; ctx.font = '800 32px -apple-system, sans-serif';
  ctx.fillText('Swish Strike', W / 2, 58);

  // The hero of the card: the actual made-shot arc through the hoop.
  drawShotArc(ctx, { x: 60, y: 88, w: 420, h: 240 }, accent);

  ctx.textAlign = 'center';
  ctx.fillStyle = accent; ctx.font = '900 150px -apple-system, sans-serif';
  ctx.fillText(String(total), W / 2, 482);
  ctx.fillStyle = '#9BA3B0'; ctx.font = '600 22px -apple-system, sans-serif';
  ctx.fillText(`${S.game.title} · ${S.game.tag}`, W / 2, 518);

  const evs = S.engine.events || [];
  const sw = evs.filter((e) => e.quality === 'swish').length;
  const rim = evs.filter((e) => e.quality === 'rim').length;
  if (sw + rim > 0) {
    ctx.fillStyle = accent; ctx.font = '700 18px -apple-system, sans-serif';
    ctx.fillText(`${sw} swish · ${rim} off the rim`, W / 2, 552);
  }

  if (stats.length > 1) {
    ctx.font = '600 22px -apple-system, sans-serif';
    stats.sort((a, b) => b.count - a.count).slice(0, 3).forEach((p, i) => {
      ctx.fillStyle = i === 0 ? accent : '#F4F6FA';
      const line = `${p.name}   ${p.count}`, y = 596 + i * 40;
      ctx.fillText(line, W / 2, y);
      if (i === 0) drawCrown(ctx, W / 2 - ctx.measureText(line).width / 2 - 38, y - 18, accent);
    });
  }
}

// Draw the frozen made-shot arc (S.savedArc) and the target zone inside a panel.
function drawShotArc(ctx, r, accent) {
  ctx.save();
  roundRect(ctx, r.x, r.y, r.w, r.h, 18); ctx.fillStyle = '#15171C'; ctx.fill();
  roundRect(ctx, r.x, r.y, r.w, r.h, 18); ctx.strokeStyle = 'rgba(255,255,255,0.08)'; ctx.lineWidth = 1; ctx.stroke();
  ctx.textAlign = 'left'; ctx.fillStyle = '#9BA3B0';
  ctx.font = '700 11px -apple-system, sans-serif';
  ctx.fillText('THE SHOT', r.x + 16, r.y + 24);

  const pad = 22, ix = r.x + pad, iy = r.y + pad + 8, iw = r.w - pad * 2, ih = r.h - pad * 2 - 8;
  const mapX = (nx) => ix + Math.min(1, Math.max(0, nx)) * iw;
  const mapY = (ny) => iy + Math.min(1, Math.max(0, ny)) * ih;

  const z = S.activeZone;
  if (z) { // the hoop/target the ball fell through
    ctx.setLineDash([8, 6]); ctx.strokeStyle = accent + '88'; ctx.lineWidth = 2;
    ctx.strokeRect(mapX(z.left), mapY(z.top), (z.right - z.left) * iw, (z.bottom - z.top) * ih);
    ctx.setLineDash([]);
  }

  const arc = S.savedArc || [];
  if (arc.length > 1) {
    for (let i = 1; i < arc.length; i++) {
      const a = arc[i - 1], b = arc[i], f = i / arc.length; // brighter toward the make
      ctx.strokeStyle = accent; ctx.globalAlpha = 0.25 + f * 0.65;
      ctx.lineWidth = 2 + f * 5; ctx.lineCap = 'round';
      ctx.beginPath(); ctx.moveTo(mapX(a.x), mapY(a.y)); ctx.lineTo(mapX(b.x), mapY(b.y)); ctx.stroke();
    }
    const end = arc[arc.length - 1];
    ctx.globalAlpha = 1; ctx.fillStyle = '#fff';
    ctx.beginPath(); ctx.arc(mapX(end.x), mapY(end.y), 6, 0, 7); ctx.fill();
  } else {
    ctx.globalAlpha = 1; ctx.fillStyle = '#9BA3B0'; ctx.textAlign = 'center';
    ctx.font = '600 13px -apple-system, sans-serif';
    ctx.fillText('—', r.x + r.w / 2, r.y + r.h / 2);
  }
  ctx.restore();
}

// ---------------- count / celebration ----------------
function updateCount(n) { const el = $('#count'); if (el) el.textContent = String(n); }
function pulse(quality) {
  if (reduceMotion) return;
  const el = $('#count'); el.classList.remove('pop'); void el.offsetWidth; el.classList.add('pop');
  const p = $('#pulse');
  p.classList.remove('fire', 'swish', 'rim'); void p.offsetWidth;
  if (quality) p.classList.add(quality); // swish = clean green ring, rim = amber ring
  p.classList.add('fire');
  setTimeout(() => el.classList.remove('pop'), 220);
}
function missFlash() {
  if (reduceMotion) return;
  const el = $('#count'); el.classList.remove('miss'); void el.offsetWidth; el.classList.add('miss');
  setTimeout(() => el.classList.remove('miss'), 420);
}
let toastTimer = 0;
function toast(msg) {
  const el = $('#toast'); el.textContent = msg; el.classList.add('show');
  clearTimeout(toastTimer); toastTimer = setTimeout(() => el.classList.remove('show'), 1300);
}

// ---------------- loop ----------------
function startLoop() {
  if (S.running) return;
  S.running = true; S.t0 = performance.now();
  const tick = async () => {
    if (!S.running) return;
    const t = (performance.now() - S.t0) / 1000;
    const tPhase = (performance.now() - S.phaseT0) / 1000;
    try {
      if (S.phase === 'setup') setupTick(tPhase);
      else if (S.phase === 'play') await playFrame(t);
    } catch (e) { console.warn('tick error', e); }
    S.raf = requestAnimationFrame(tick);
  };
  if (!S.sim) S.sim = makeSimSource(S.game); // safety net; openGame owns the sim
  tick();
}
function stopLoop() { S.running = false; cancelAnimationFrame(S.raf); }

// ---------------- camera ----------------
let stream = null;
async function startCamera() {
  if (!navigator.mediaDevices?.getUserMedia) return false;
  if (!S.detector) { S.detector = new HybridBallDetector({ hue: S.game.ballHue }); await S.detector.load(); }
  if (!S.pose) { S.pose = new PoseDetector(); await S.pose.load(); }
  try {
    stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' }, audio: false });
    S.video.srcObject = stream; await S.video.play(); $('#video').style.display = 'block';
    return true;
  } catch { return false; }
}
function stopCamera() {
  if (stream) { stream.getTracks().forEach((t) => t.stop()); stream = null; }
  if (S.video) { S.video.srcObject = null; S.video.style.display = 'none'; }
}

async function setSource(src) {
  S.source = src;
  $('#src-sim').classList.toggle('on', src === 'sim');
  $('#src-cam').classList.toggle('on', src === 'cam');
  if (src === 'cam') { const ok = await startCamera(); if (!ok) { S.source = 'sim'; $('#src-sim').classList.add('on'); $('#src-cam').classList.remove('on'); toast('Camera/model unavailable — using Simulation'); } }
  else stopCamera();
}

function backHome() { stopLoop(); stopCamera(); showScreen('home'); renderHome(); }

// ---------------- wire ----------------
function init() {
  renderHome();
  $('#game-back').addEventListener('click', backHome);
  $('#setup-start').addEventListener('click', () => { if (!$('#setup-start').disabled) enterPlay(); });

  // voice mute toggle (persisted)
  const vb = $('#voice-btn');
  const voiceLabel = () => {
    vb.innerHTML = Voice.on ? ICONS.speakerOn : ICONS.speakerOff;
    vb.title = Voice.on ? 'Voice callouts on' : 'Voice callouts off';
    vb.setAttribute('aria-label', vb.title);
  };
  voiceLabel();
  vb.addEventListener('click', () => {
    sfx.unlock();
    const on = Voice.toggle();      // master audio toggle: voice callouts + game SFX
    sfx.muted = !on;
    localStorage.setItem('swishstrike.sfx', on ? 'on' : 'off');
    voiceLabel();
    toast(on ? 'Sound on' : 'Sound off');
  });

  // share card: download the generated PNG
  $('#share-save').addEventListener('click', () => {
    try {
      const a = document.createElement('a');
      a.download = `swish-strike-${S.game ? S.game.slug : 'score'}.png`;
      a.href = $('#share-card').toDataURL('image/png');
      a.click();
    } catch { toast('Could not save the card'); }
  });
  $('#finish-btn').addEventListener('click', finishGame);
  $('#again-btn').addEventListener('click', () => { enterSetup(); });
  $('#result-home').addEventListener('click', backHome);
  $('#src-sim').addEventListener('click', () => setSource('sim'));
  $('#src-cam').addEventListener('click', () => setSource('cam'));

  // tap-to-place override during setup/play (zone games)
  $('#stage').addEventListener('click', (e) => {
    if (e.target.closest('button')) return;
    if (!S.game || !isZoneGame(S.game.ruleSpec) || !S.canvas) return;
    const r = S.canvas.getBoundingClientRect();
    const nx = clamp01((e.clientX - r.left) / r.width), ny = clamp01((e.clientY - r.top) / r.height);
    const z0 = S.game.ruleSpec.zone; const hw = (z0.right - z0.left) / 2, hh = (z0.bottom - z0.top) / 2;
    S.activeZone = { left: clamp01(nx - hw), top: clamp01(ny - hh), right: clamp01(nx + hw), bottom: clamp01(ny + hh) };
    if (S.phase === 'play') { S.engine = new CountingEngine(currentRule()); updateCount(0); }
    toast('Target placed');
  });

  // PWA: register the service worker (offline app shell). Localhost + https only.
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('sw.js').catch(() => { /* not fatal */ });
  }

  // headless test API
  window.swishTest = {
    games: GAMES.map((g) => g.slug),
    openGame,
    phase: () => S.phase,
    screen: () => S.screen,
    count: () => S.engine?.count ?? 0,
    players: () => (S.registry ? S.registry.stats() : []),
    activeZone: () => S.activeZone,
    qualities: () => (S.engine?.events || []).map((e) => e.quality).filter(Boolean),
    savedArc: () => S.savedArc || [],
    heat: () => (S.heat ? S.heat.level : 0),
    misses: () => (S.engine?.events || []).filter((e) => e.type === 'miss').length,
    maxStreak: () => S.maxStreak,
    finish: finishGame,
    setSource,
  };
}
document.addEventListener('DOMContentLoaded', init);
