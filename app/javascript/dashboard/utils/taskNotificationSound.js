// Synthesised 2-tone chime for Task notifications.
//
// We avoid binary audio assets so the bundle stays lean and the chime
// timbre can adapt to urgency: urgent tasks land a tone a perfect fourth
// above the baseline, low-priority events stay subtle.
//
// The function is a noop if the Web Audio API is unavailable (SSR or
// blocked browsers) and resolves the AudioContext lazily so we never
// instantiate one until the user opts in.

let cachedContext = null;

const getAudioContext = () => {
  if (typeof window === 'undefined') return null;
  if (cachedContext) return cachedContext;
  const Ctor = window.AudioContext || window.webkitAudioContext;
  if (!Ctor) return null;
  try {
    cachedContext = new Ctor();
  } catch (_e) {
    cachedContext = null;
  }
  return cachedContext;
};

const URGENCY_FREQUENCIES = {
  urgent: [880, 1175],
  high: [784, 1047],
  medium: [659, 880],
  low: [523, 659],
  none: [523, 659],
};

const playTone = (ctx, frequency, startAt, duration, gainPeak) => {
  const oscillator = ctx.createOscillator();
  const gain = ctx.createGain();
  oscillator.type = 'sine';
  oscillator.frequency.value = frequency;

  // Plucked envelope (fast attack, exponential decay) — feels closer to a
  // soft chime than a synthy beep.
  gain.gain.setValueAtTime(0.0001, startAt);
  gain.gain.exponentialRampToValueAtTime(gainPeak, startAt + 0.015);
  gain.gain.exponentialRampToValueAtTime(0.0001, startAt + duration);

  oscillator.connect(gain).connect(ctx.destination);
  oscillator.start(startAt);
  oscillator.stop(startAt + duration + 0.05);
};

export const playNotificationSound = (urgency = 'medium') => {
  const ctx = getAudioContext();
  if (!ctx) return;
  // Suspended contexts must be resumed inside the user gesture that
  // toggled sound on — but a best-effort resume here covers tabs that
  // come back from sleep.
  if (ctx.state === 'suspended' && ctx.resume) {
    ctx.resume().catch(() => {});
  }
  const [base, harmonic] =
    URGENCY_FREQUENCIES[urgency] || URGENCY_FREQUENCIES.medium;
  const now = ctx.currentTime + 0.001;
  playTone(ctx, base, now, 0.32, 0.18);
  playTone(ctx, harmonic, now + 0.12, 0.28, 0.14);
};

export const resetCachedAudioContextForTests = () => {
  cachedContext = null;
};
