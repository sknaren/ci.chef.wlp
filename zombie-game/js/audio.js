// All sound effects are synthesised with the Web Audio API - no audio files needed.
let ctx = null, master = null, noiseBuf = null, muted = false;
let bike = null, wind = null;

function out() { return master; }

function burst({ dur = 0.2, type = 'lowpass', f0 = 800, f1 = null, q = 1, vol = 0.5, at = 0, attack = 0.004 }) {
  if (!ctx || vol <= 0.001) return;
  const t = ctx.currentTime + at;
  const s = ctx.createBufferSource(); s.buffer = noiseBuf; s.loop = true;
  const f = ctx.createBiquadFilter(); f.type = type; f.Q.value = q;
  f.frequency.setValueAtTime(f0, t);
  if (f1) f.frequency.exponentialRampToValueAtTime(f1, t + dur);
  const g = ctx.createGain();
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(vol, t + attack);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  s.connect(f); f.connect(g); g.connect(out());
  s.start(t, Math.random() * 1.5); s.stop(t + dur + 0.05);
}

function tone({ type = 'sine', f0 = 440, f1 = null, dur = 0.2, vol = 0.3, at = 0, attack = 0.005, vib = 0, vibRate = 6, lp = null }) {
  if (!ctx || vol <= 0.001) return;
  const t = ctx.currentTime + at;
  const o = ctx.createOscillator(); o.type = type;
  o.frequency.setValueAtTime(f0, t);
  if (f1) o.frequency.exponentialRampToValueAtTime(f1, t + dur);
  const g = ctx.createGain();
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(vol, t + attack);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  let node = o;
  if (lp) { const f = ctx.createBiquadFilter(); f.type = 'lowpass'; f.frequency.value = lp; o.connect(f); node = f; }
  node.connect(g); g.connect(out());
  if (vib) {
    const l = ctx.createOscillator(); l.frequency.value = vibRate;
    const lg = ctx.createGain(); lg.gain.value = vib;
    l.connect(lg); lg.connect(o.frequency);
    l.start(t); l.stop(t + dur + 0.05);
  }
  o.start(t); o.stop(t + dur + 0.05);
}

// distance -> volume (1 right next to the listener)
export function falloff(d, ref = 8) { return 1 / (1 + Math.pow(d / ref, 1.6)); }

export const A = {
  init() {
    if (ctx) return;
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    ctx = new AC();
    master = ctx.createGain(); master.gain.value = 0.7;
    const comp = ctx.createDynamicsCompressor();
    master.connect(comp); comp.connect(ctx.destination);
    noiseBuf = ctx.createBuffer(1, ctx.sampleRate * 2, ctx.sampleRate);
    const d = noiseBuf.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
    // night wind bed
    const s = ctx.createBufferSource(); s.buffer = noiseBuf; s.loop = true;
    const f = ctx.createBiquadFilter(); f.type = 'bandpass'; f.frequency.value = 380; f.Q.value = 0.7;
    const lfo = ctx.createOscillator(); lfo.frequency.value = 0.13;
    const lg = ctx.createGain(); lg.gain.value = 160;
    lfo.connect(lg); lg.connect(f.frequency);
    const g = ctx.createGain(); g.gain.value = 0;
    s.connect(f); f.connect(g); g.connect(master);
    s.start(); lfo.start();
    wind = g;
  },
  resume() { if (ctx && ctx.state === 'suspended') ctx.resume(); },
  toggleMute() { muted = !muted; if (master) master.gain.value = muted ? 0 : 0.7; return muted; },
  ready() { return !!ctx; },

  // ambience: dark 0..1. Wind swells at night, crickets chirp.
  ambient(dark, dt) {
    if (!ctx) return;
    wind.gain.setTargetAtTime(0.02 + dark * 0.09, ctx.currentTime, 0.5);
    if (dark > 0.5 && Math.random() < dt * 1.6) {
      const f = 4200 + Math.random() * 600;
      for (let i = 0; i < 3; i++) tone({ type: 'sine', f0: f, dur: 0.05, vol: 0.012, at: i * 0.08 });
    }
  },

  click() { tone({ type: 'square', f0: 700, f1: 500, dur: 0.06, vol: 0.06 }); },
  step(vol = 0.1) { burst({ dur: 0.07, f0: 520, f1: 200, vol: vol * 0.7 }); },
  pickup() {
    tone({ type: 'sine', f0: 660, dur: 0.12, vol: 0.18 });
    tone({ type: 'sine', f0: 990, dur: 0.18, vol: 0.18, at: 0.09 });
  },
  empty() { tone({ type: 'square', f0: 220, f1: 160, dur: 0.05, vol: 0.1 }); },
  heal() {
    tone({ type: 'triangle', f0: 400, f1: 800, dur: 0.35, vol: 0.2 });
    tone({ type: 'triangle', f0: 600, f1: 1200, dur: 0.35, vol: 0.15, at: 0.15 });
  },

  gun(v = 1) {
    burst({ dur: 0.22, type: 'bandpass', f0: 2600, f1: 500, q: 0.7, vol: 0.55 * v });
    burst({ dur: 0.5, f0: 700, f1: 90, vol: 0.28 * v, at: 0.01 });
    tone({ type: 'sine', f0: 140, f1: 38, dur: 0.22, vol: 0.55 * v });
  },
  bat(hit = false) {
    burst({ dur: 0.16, type: 'highpass', f0: 600, f1: 2500, vol: 0.18, attack: 0.05 });
    if (hit) { tone({ type: 'sine', f0: 170, f1: 60, dur: 0.15, vol: 0.4, at: 0.08 }); burst({ dur: 0.1, f0: 900, vol: 0.3, at: 0.08 }); }
  },
  thud(v = 0.4) { tone({ type: 'sine', f0: 120, f1: 45, dur: 0.14, vol: v }); burst({ dur: 0.08, f0: 500, vol: v * 0.5 }); },
  hurt() {
    tone({ type: 'sawtooth', f0: 260, f1: 110, dur: 0.28, vol: 0.28, lp: 1400 });
    burst({ dur: 0.12, f0: 700, vol: 0.2 });
  },
  death() {
    tone({ type: 'sawtooth', f0: 220, f1: 40, dur: 1.2, vol: 0.35, lp: 900 });
    tone({ type: 'sine', f0: 90, f1: 30, dur: 1.4, vol: 0.5 });
  },
  groan(v = 1) {
    const f = 90 + Math.random() * 40;
    tone({ type: 'sawtooth', f0: f * 1.4, f1: f * 0.55, dur: 0.9, vol: 0.5 * v, vib: 12, vibRate: 5 + Math.random() * 3, lp: 520 });
    burst({ dur: 0.7, type: 'bandpass', f0: 500, f1: 260, q: 2, vol: 0.18 * v, attack: 0.15 });
  },
  zombieHit(v = 1) { tone({ type: 'sawtooth', f0: 150, f1: 70, dur: 0.18, vol: 0.3 * v, lp: 700 }); },
  zombieDie(v = 1) { tone({ type: 'sawtooth', f0: 130, f1: 35, dur: 0.8, vol: 0.4 * v, lp: 500, vib: 8 }); },

  doorOpen(v = 1) {
    tone({ type: 'sawtooth', f0: 95, f1: 180, dur: 0.6, vol: 0.12 * v, lp: 700, vib: 14, vibRate: 22 });
    burst({ dur: 0.5, f0: 300, f1: 900, q: 3, type: 'bandpass', vol: 0.12 * v, attack: 0.1 });
    tone({ type: 'sine', f0: 110, f1: 50, dur: 0.1, vol: 0.3 * v, at: 0.55 });
  },
  doorClose(v = 1) {
    tone({ type: 'sawtooth', f0: 170, f1: 90, dur: 0.45, vol: 0.1 * v, lp: 700, vib: 12, vibRate: 20 });
    tone({ type: 'sine', f0: 130, f1: 40, dur: 0.16, vol: 0.5 * v, at: 0.42 });
    burst({ dur: 0.12, f0: 700, vol: 0.25 * v, at: 0.42 });
  },
  doorBreak(v = 1) {
    burst({ dur: 0.5, f0: 1800, f1: 200, vol: 0.6 * v });
    tone({ type: 'sine', f0: 100, f1: 30, dur: 0.4, vol: 0.6 * v });
  },
  cupboardOpen() {
    tone({ type: 'sawtooth', f0: 220, f1: 420, dur: 0.5, vol: 0.09, lp: 1200, vib: 20, vibRate: 28 });
    burst({ dur: 0.4, type: 'bandpass', f0: 800, f1: 1500, q: 4, vol: 0.1, attack: 0.1 });
    tone({ type: 'sine', f0: 180, f1: 90, dur: 0.08, vol: 0.25, at: 0.45 });
  },
  cupboardClose() {
    tone({ type: 'sawtooth', f0: 420, f1: 230, dur: 0.35, vol: 0.08, lp: 1200, vib: 20, vibRate: 28 });
    tone({ type: 'sine', f0: 200, f1: 80, dur: 0.1, vol: 0.35, at: 0.32 });
    burst({ dur: 0.08, f0: 900, vol: 0.2, at: 0.32 });
  },
  lootPop(i = 0) { tone({ type: 'sine', f0: 500 + i * 120, f1: 900 + i * 120, dur: 0.15, vol: 0.12 }); },

  // --- motorbike: ignition + continuous engine controlled by speed
  bikeStart() {
    if (!ctx) return;
    for (let i = 0; i < 3; i++) {
      tone({ type: 'sawtooth', f0: 70 + i * 6, f1: 40, dur: 0.16, vol: 0.22, at: i * 0.17, lp: 500 });
      burst({ dur: 0.12, f0: 400, vol: 0.2, at: i * 0.17 });
    }
    if (bike) return;
    const o1 = ctx.createOscillator(); o1.type = 'sawtooth'; o1.frequency.value = 40;
    const o2 = ctx.createOscillator(); o2.type = 'square'; o2.frequency.value = 20;
    const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 400; lp.Q.value = 3;
    const g = ctx.createGain(); g.gain.value = 0;
    const chug = ctx.createOscillator(); chug.frequency.value = 9;
    const chugG = ctx.createGain(); chugG.gain.value = 0.05;
    chug.connect(chugG); chugG.connect(g.gain);
    o1.connect(lp); o2.connect(lp); lp.connect(g); g.connect(master);
    const t = ctx.currentTime + 0.5;
    g.gain.setValueAtTime(0, ctx.currentTime);
    g.gain.linearRampToValueAtTime(0.16, t);
    o1.start(); o2.start(); chug.start();
    bike = { o1, o2, lp, g, chug };
  },
  bikeUpdate(speed01, throttle) {
    if (!bike) return;
    const t = ctx.currentTime;
    const rpm = 38 + speed01 * 100 + throttle * 20;
    bike.o1.frequency.setTargetAtTime(rpm, t, 0.08);
    bike.o2.frequency.setTargetAtTime(rpm * 0.503, t, 0.08);
    bike.lp.frequency.setTargetAtTime(380 + speed01 * 1500 + throttle * 350, t, 0.1);
    bike.chug.frequency.setTargetAtTime(8 + speed01 * 30, t, 0.1);
    bike.g.gain.setTargetAtTime(0.16 + speed01 * 0.16 + throttle * 0.04, t, 0.1);
  },
  bikeStop() {
    if (!bike) return;
    const b = bike; bike = null;
    const t = ctx.currentTime;
    b.g.gain.cancelScheduledValues(t);
    b.g.gain.setTargetAtTime(0, t, 0.15);
    b.o1.stop(t + 0.8); b.o2.stop(t + 0.8); b.chug.stop(t + 0.8);
  },
  bikeCrash(v = 1) { burst({ dur: 0.3, f0: 1200, f1: 150, vol: 0.5 * v }); tone({ type: 'sine', f0: 100, f1: 35, dur: 0.3, vol: 0.5 * v }); },

  gameOver() {
    [392, 330, 262, 196].forEach((f, i) => tone({ type: 'triangle', f0: f, dur: 0.7, vol: 0.25, at: i * 0.45 }));
  },
  dawn() { [262, 330, 392, 523].forEach((f, i) => tone({ type: 'sine', f0: f, dur: 0.9, vol: 0.12, at: i * 0.25 })); },
  dusk() { [392, 311, 262].forEach((f, i) => tone({ type: 'sine', f0: f, dur: 1.1, vol: 0.12, at: i * 0.3 })); },
};
