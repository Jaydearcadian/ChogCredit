/**
 * Sound and haptics, from docs/brand/DESIGN.md "Sound and haptics". One idea: a stamp. Sound is OFF by default and is
 * offered once, after the first confirmed transaction. Risk-alert sounds are a separate switch, also off. Haptics are
 * on where the device supports them and off when it asks for reduced motion. Nothing here carries information alone.
 */
export type Cue = 'door' | 'confirmed' | 'final' | 'repaid' | 'error' | 'risk' | 'liquidatable' | 'paused' | 'bubble' | 'submitted';

type Prefs = { sound: boolean; riskSound: boolean; haptics: boolean; offered: boolean };
const KEY = 'chog-credit:prefs';
const DEFAULTS: Prefs = { sound: false, riskSound: false, haptics: true, offered: false };

export function getPrefs(): Prefs {
  try { return { ...DEFAULTS, ...JSON.parse(localStorage.getItem(KEY) ?? '{}') }; } catch { return DEFAULTS; }
}
export function setPrefs(p: Partial<Prefs>) {
  try { localStorage.setItem(KEY, JSON.stringify({ ...getPrefs(), ...p })); } catch { /* storage can be blocked */ }
  listeners.forEach((l) => l());
}
const listeners = new Set<() => void>();
export const onPrefs = (l: () => void) => { listeners.add(l); return () => { listeners.delete(l); }; };

const reduced = () => typeof matchMedia !== 'undefined' && matchMedia('(prefers-reduced-motion: reduce)').matches;

const BUZZ: Record<Cue, number[]> = {
  door: [25], submitted: [8], confirmed: [15, 40, 15], final: [12], repaid: [10, 30, 10, 30, 20],
  error: [30, 50, 30], risk: [20, 60, 20], liquidatable: [40, 60, 40, 60, 40], paused: [10], bubble: [],
};

let ctx: AudioContext | null = null;
function tones(cue: Cue) {
  const C = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
  if (!C) return;
  ctx ??= new C();
  if (ctx.state === 'suspended') void ctx.resume();
  const ac = ctx, t = ac.currentTime;
  const tone = (f: number, s: number, d: number, type: OscillatorType, v: number, f2?: number) => {
    const o = ac.createOscillator(), g = ac.createGain();
    o.type = type; o.frequency.setValueAtTime(f, t + s);
    if (f2) o.frequency.linearRampToValueAtTime(f2, t + s + d);
    g.gain.setValueAtTime(0.0001, t + s); g.gain.exponentialRampToValueAtTime(v, t + s + 0.012); g.gain.exponentialRampToValueAtTime(0.0001, t + s + d);
    o.connect(g); g.connect(ac.destination); o.start(t + s); o.stop(t + s + d + 0.03);
  };
  switch (cue) {
    case 'door': tone(130, 0, 0.16, 'sine', 0.2, 70); tone(1800, 0, 0.02, 'triangle', 0.03); break;
    case 'confirmed': tone(659.25, 0, 0.11, 'triangle', 0.1); tone(987.77, 0.09, 0.17, 'triangle', 0.1); break;
    case 'final': tone(784, 0, 0.14, 'sine', 0.07); break;
    case 'repaid': tone(523.25, 0, 0.1, 'triangle', 0.1); tone(659.25, 0.09, 0.1, 'triangle', 0.1); tone(783.99, 0.18, 0.2, 'triangle', 0.1); break;
    case 'error': tone(330, 0, 0.1, 'triangle', 0.1); tone(277, 0.09, 0.16, 'triangle', 0.1); break;
    case 'risk': tone(220, 0, 0.07, 'sine', 0.14); tone(220, 0.14, 0.07, 'sine', 0.14); break;
    case 'liquidatable': tone(196, 0, 0.09, 'sine', 0.14); tone(196, 0.16, 0.09, 'sine', 0.14); tone(196, 0.32, 0.09, 'sine', 0.14); break;
    case 'paused': tone(494, 0, 0.1, 'sine', 0.08); tone(392, 0.1, 0.2, 'sine', 0.08); break;
    case 'bubble': tone(520, 0, 0.08, 'sine', 0.08, 880); break;
    case 'submitted': break; // nothing, on purpose
  }
}

let confirmed = false;
export const confirmedOnce = () => confirmed;

export function cue(c: Cue) {
  if (c === 'confirmed' || c === 'door' || c === 'repaid') { if (!confirmed) { confirmed = true; listeners.forEach((l) => l()); } }
  const p = getPrefs();
  try {
    if (p.haptics && !reduced() && BUZZ[c].length && typeof navigator !== 'undefined' && 'vibrate' in navigator) navigator.vibrate(BUZZ[c]);
    const isRisk = c === 'risk' || c === 'liquidatable';
    if ((isRisk ? p.sound && p.riskSound : p.sound)) tones(c);
  } catch { /* audio or vibration can be blocked; the screen still says everything */ }
}
