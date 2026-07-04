// sfx.js
// ----------------------------------------------------------------------------
// Synthesized sound effects via the Web Audio API — NO audio files (keeps the
// repo self-contained and license-clean, same stance as the SVG hero art). Each
// effect is built from oscillators / filtered noise at call time:
//   • swish — filtered white-noise whoosh (a clean net)
//   • rim   — two short metallic clanks (a rattle)
//   • streak — a bright rising two-note chime (you're heating up)
//   • pb    — a three-note arpeggio (new personal best)
// Audio is unlocked on the first user gesture (browser autoplay policy); every
// method is guarded so a missing/!suspended AudioContext can never throw — the
// headless test's "no fatal console errors" check depends on that.
// ----------------------------------------------------------------------------

const AC = typeof window !== 'undefined' && (window.AudioContext || window.webkitAudioContext);

export class Sfx {
  constructor() {
    this.muted = localStorage.getItem('swishstrike.sfx') === 'off';
    this.ctx = null;
    this.master = null;
  }

  /** Create/resume the AudioContext. Call from a user gesture to unlock audio. */
  unlock() {
    if (!AC) return;
    try {
      if (!this.ctx) {
        this.ctx = new AC();
        this.master = this.ctx.createGain();
        this.master.gain.value = 0.9;
        this.master.connect(this.ctx.destination);
      }
      if (this.ctx.state === 'suspended') this.ctx.resume();
    } catch { /* audio unavailable — stay silent */ }
  }

  toggle() {
    this.muted = !this.muted;
    localStorage.setItem('swishstrike.sfx', this.muted ? 'off' : 'on');
    return !this.muted;
  }

  _ready() {
    if (this.muted || !this.ctx || this.ctx.state !== 'running') return null;
    return this.ctx;
  }

  // --- voices ---------------------------------------------------------------

  /** One oscillator note with an exponential pluck envelope. */
  _tone(freq, at, dur, type = 'sine', peak = 0.25) {
    const ctx = this.ctx;
    const o = ctx.createOscillator(), g = ctx.createGain();
    o.type = type; o.frequency.setValueAtTime(freq, at);
    g.gain.setValueAtTime(0.0001, at);
    g.gain.exponentialRampToValueAtTime(peak, at + 0.008);
    g.gain.exponentialRampToValueAtTime(0.0001, at + dur);
    o.connect(g).connect(this.master);
    o.start(at); o.stop(at + dur + 0.02);
  }

  /** A burst of white noise through a sweeping band-pass — the net swish. */
  swish() {
    const ctx = this._ready(); if (!ctx) return;
    const t = ctx.currentTime, dur = 0.34;
    const buf = ctx.createBuffer(1, ctx.sampleRate * dur, ctx.sampleRate);
    const d = buf.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = (Math.random() * 2 - 1) * (1 - i / d.length);
    const src = ctx.createBufferSource(); src.buffer = buf;
    const bp = ctx.createBiquadFilter(); bp.type = 'bandpass'; bp.Q.value = 0.7;
    bp.frequency.setValueAtTime(2800, t); bp.frequency.exponentialRampToValueAtTime(650, t + dur);
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.5, t); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    src.connect(bp).connect(g).connect(this.master);
    src.start(t); src.stop(t + dur);
  }

  /** Two short detuned square blips — the metallic rim rattle. */
  rim() {
    const ctx = this._ready(); if (!ctx) return;
    const t = ctx.currentTime;
    this._tone(430, t, 0.07, 'square', 0.16);
    this._tone(360, t + 0.085, 0.08, 'square', 0.14);
  }

  /** A soft generic blip for a score in non-basketball games. */
  pop() {
    const ctx = this._ready(); if (!ctx) return;
    this._tone(520, ctx.currentTime, 0.1, 'triangle', 0.18);
  }

  /** A descending tone when a streak breaks (a miss). */
  miss() {
    const ctx = this._ready(); if (!ctx) return;
    const t = ctx.currentTime;
    const o = ctx.createOscillator(), g = ctx.createGain();
    o.type = 'sawtooth';
    o.frequency.setValueAtTime(300, t);
    o.frequency.exponentialRampToValueAtTime(120, t + 0.3);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(0.16, t + 0.02);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.32);
    o.connect(g).connect(this.master);
    o.start(t); o.stop(t + 0.34);
  }

  /** A rising two-note chime when the streak heats up. */
  streak() {
    const ctx = this._ready(); if (!ctx) return;
    const t = ctx.currentTime;
    this._tone(660, t, 0.12, 'triangle', 0.2);
    this._tone(990, t + 0.1, 0.18, 'triangle', 0.2);
  }

  /** A three-note arpeggio for a new personal best. */
  pb() {
    const ctx = this._ready(); if (!ctx) return;
    const t = ctx.currentTime;
    [523, 659, 784].forEach((f, i) => this._tone(f, t + i * 0.11, 0.22, 'triangle', 0.22));
  }
}

export default { Sfx };
