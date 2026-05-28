<script setup>
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  ref,
  watch,
} from 'vue';
import { useWindowSize } from '@vueuse/core';
import Icon from 'next/icon/Icon.vue';

// Cinematic spotlight overlay — full-viewport SVG mask cuts a rounded
// "stage" around the target. Pop-over floats next to the cutout, flips to
// stay on-screen, and intensifies after 25s of inactivity so users who
// freeze on a step get nudged. Built so the tour feels like ClickUp /
// Stripe Atlas: dark backdrop, smooth zoom-in, animated pointer hand,
// pulse halo, target-click auto-advance, keyboard nav (← → Esc), optional
// SpeechSynthesis narration.
const props = defineProps({
  target: { type: Object, required: true },
  title: { type: String, required: true },
  body: { type: String, required: true },
  chapter: { type: String, default: '' },
  side: { type: String, default: 'right' },
  step: { type: Number, default: 1 },
  total: { type: Number, default: 1 },
  primaryLabel: { type: String, required: true },
  prevLabel: { type: String, required: true },
  skipLabel: { type: String, required: true },
  hint: { type: String, default: '' },
  voiceEnabled: { type: Boolean, default: false },
});

const emit = defineEmits(['next', 'prev', 'skip', 'targetClick']);

const { width: vw, height: vh } = useWindowSize();

const PAD_REST = 10;
const PAD_ZOOM = 36;
const PAD_INTENSE = 18;
const POPOVER_W = 380;
const POPOVER_H_ESTIMATE = 240;
const INACTIVITY_MS = 25000;

const targetRect = ref({ top: 0, left: 0, width: 0, height: 0 });
const entered = ref(false);
const intense = ref(false);

let inactivityTimer = null;
let activityHandlers = [];

const recompute = () => {
  const node = props.target;
  if (!node || typeof node.getBoundingClientRect !== 'function') return;
  const r = node.getBoundingClientRect();
  targetRect.value = {
    top: r.top,
    left: r.left,
    width: r.width,
    height: r.height,
  };
};

const cutoutRect = computed(() => {
  let pad = PAD_ZOOM;
  if (entered.value) pad = intense.value ? PAD_INTENSE : PAD_REST;
  return {
    x: targetRect.value.left - pad,
    y: targetRect.value.top - pad,
    width: Math.max(targetRect.value.width + pad * 2, 0),
    height: Math.max(targetRect.value.height + pad * 2, 0),
  };
});

// Pick a side that keeps the popover on-screen. Honors `side` first, flips
// to the opposite edge if it would overflow, then clamps to viewport.
const popoverPos = computed(() => {
  const t = targetRect.value;
  if (!t.width) return { top: -9999, left: -9999, side: props.side };
  const gap = 22;
  let side = props.side;
  let top = 0;
  let left = 0;

  const apply = s => {
    if (s === 'right') {
      left = t.left + t.width + gap;
      top = t.top;
    } else if (s === 'left') {
      left = t.left - POPOVER_W - gap;
      top = t.top;
    } else if (s === 'bottom') {
      left = t.left;
      top = t.top + t.height + gap;
    } else {
      left = t.left;
      top = t.top - POPOVER_H_ESTIMATE - gap;
    }
  };

  apply(side);
  if (side === 'right' && left + POPOVER_W > vw.value - 16) {
    side = 'left';
    apply(side);
  }
  if (side === 'left' && left < 16) {
    side = 'right';
    apply(side);
  }
  if (side === 'bottom' && top + POPOVER_H_ESTIMATE > vh.value - 16) {
    side = 'top';
    apply(side);
  }
  if (side === 'top' && top < 16) {
    side = 'bottom';
    apply(side);
  }
  left = Math.max(16, Math.min(left, vw.value - POPOVER_W - 16));
  top = Math.max(16, Math.min(top, vh.value - POPOVER_H_ESTIMATE - 16));
  return { top, left, side };
});

// ClickUp-style animated pointer — a hand emoji-free SVG that sits on the
// target's edge facing the popover. Position depends on the chosen side so
// it points *from* the target *to* the narrator. Hidden once the user
// clicks the target (handled upstream via `targetClick`).
const pointerPos = computed(() => {
  const t = targetRect.value;
  if (!t.width) return { top: -9999, left: -9999, rotate: 0 };
  const side = popoverPos.value.side;
  if (side === 'right') {
    return {
      top: t.top + t.height / 2 - 14,
      left: t.left + t.width + 4,
      rotate: 0,
    };
  }
  if (side === 'left') {
    return {
      top: t.top + t.height / 2 - 14,
      left: t.left - 32,
      rotate: 180,
    };
  }
  if (side === 'bottom') {
    return {
      top: t.top + t.height + 4,
      left: t.left + t.width / 2 - 14,
      rotate: 90,
    };
  }
  return {
    top: t.top - 32,
    left: t.left + t.width / 2 - 14,
    rotate: -90,
  };
});

const startInactivityTimer = () => {
  if (inactivityTimer) window.clearTimeout(inactivityTimer);
  intense.value = false;
  inactivityTimer = window.setTimeout(() => {
    intense.value = true;
  }, INACTIVITY_MS);
};

const handleActivity = () => {
  if (intense.value) intense.value = false;
  startInactivityTimer();
};

const handleDocClick = event => {
  if (props.target?.contains?.(event.target)) {
    emit('targetClick');
  }
  handleActivity();
};

const handleKey = event => {
  if (event.key === 'Escape') {
    emit('skip');
  } else if (event.key === 'ArrowRight' || event.key === 'Enter') {
    emit('next');
  } else if (event.key === 'ArrowLeft') {
    emit('prev');
  }
  handleActivity();
};

// Best-effort narration — only fires if the browser supports
// SpeechSynthesis AND the user has opted in via `voiceEnabled`. Cancels
// any in-flight speech on step change so chapters never overlap.
const speak = text => {
  if (!props.voiceEnabled) return;
  if (typeof window === 'undefined') return;
  if (!('speechSynthesis' in window)) return;
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  try {
    window.speechSynthesis.cancel();
    const utter = new SpeechSynthesisUtterance(text);
    utter.rate = 1.05;
    utter.pitch = 1;
    utter.volume = 0.8;
    window.speechSynthesis.speak(utter);
  } catch (_) {
    /* noop */
  }
};

watch(
  () => props.target,
  () => {
    entered.value = false;
    intense.value = false;
    recompute();
    nextTick(() => {
      requestAnimationFrame(() => {
        entered.value = true;
      });
    });
    startInactivityTimer();
    speak(`${props.title}. ${props.body}`);
  }
);

onMounted(() => {
  recompute();
  props.target?.scrollIntoView?.({ block: 'center', behavior: 'smooth' });
  // Two-frame wait so scrollIntoView settles before we measure — otherwise
  // the cutout briefly anchors to the pre-scroll rect.
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      recompute();
      entered.value = true;
    });
  });
  window.addEventListener('resize', recompute);
  window.addEventListener('scroll', recompute, true);
  document.addEventListener('click', handleDocClick, true);
  document.addEventListener('keydown', handleKey);

  // Mouse + touch activity resets the inactivity timer so the spotlight
  // only intensifies when the user truly froze.
  const activity = () => handleActivity();
  ['mousemove', 'touchstart'].forEach(evt => {
    document.addEventListener(evt, activity, { passive: true });
    activityHandlers.push([evt, activity]);
  });
  startInactivityTimer();
  speak(`${props.title}. ${props.body}`);
});

onBeforeUnmount(() => {
  window.removeEventListener('resize', recompute);
  window.removeEventListener('scroll', recompute, true);
  document.removeEventListener('click', handleDocClick, true);
  document.removeEventListener('keydown', handleKey);
  activityHandlers.forEach(([evt, fn]) =>
    document.removeEventListener(evt, fn)
  );
  activityHandlers = [];
  if (inactivityTimer) window.clearTimeout(inactivityTimer);
  if (typeof window !== 'undefined' && 'speechSynthesis' in window) {
    try {
      window.speechSynthesis.cancel();
    } catch (_) {
      /* noop */
    }
  }
});

const popoverShiftClass = computed(() => {
  if (!entered.value) return 'opacity-0 translate-y-2 scale-[0.97]';
  return 'opacity-100 translate-y-0 scale-100';
});
</script>

<template>
  <Teleport to="body">
    <div
      class="fixed inset-0 z-[200] pointer-events-none"
      role="dialog"
      aria-modal="true"
      :aria-label="title"
    >
      <svg
        :width="vw"
        :height="vh"
        class="absolute inset-0 motion-safe:[&_rect]:transition-all motion-safe:[&_rect]:duration-[600ms] motion-safe:[&_rect]:ease-[cubic-bezier(0.16,1,0.3,1)]"
      >
        <defs>
          <mask id="onboarding-spotlight-mask">
            <rect :width="vw" :height="vh" fill="white" />
            <rect
              :x="cutoutRect.x"
              :y="cutoutRect.y"
              :width="cutoutRect.width"
              :height="cutoutRect.height"
              rx="14"
              ry="14"
              fill="black"
            />
          </mask>
          <linearGradient
            id="onboarding-spotlight-ring"
            x1="0"
            y1="0"
            x2="1"
            y2="1"
          >
            <stop offset="0%" stop-color="#13CB8D" stop-opacity="0.95" />
            <stop offset="100%" stop-color="#60E8B8" stop-opacity="0.6" />
          </linearGradient>
          <radialGradient id="onboarding-spotlight-beam" cx="50%" cy="50%">
            <stop offset="0%" stop-color="#13CB8D" stop-opacity="0.18" />
            <stop offset="100%" stop-color="#13CB8D" stop-opacity="0" />
          </radialGradient>
        </defs>
        <!-- Darken everything except the cutout. Pure black (not slate)
             so the spotlight reads as a real stage cutout against the
             dashboard chrome instead of a tinted overlay. -->
        <rect
          :width="vw"
          :height="vh"
          fill="rgb(0 0 0 / 0.92)"
          mask="url(#onboarding-spotlight-mask)"
        />
        <!-- Soft beam glow centered on the target -->
        <circle
          :cx="targetRect.left + targetRect.width / 2"
          :cy="targetRect.top + targetRect.height / 2"
          :r="Math.max(targetRect.width, targetRect.height) * 1.4"
          fill="url(#onboarding-spotlight-beam)"
        />
        <!-- Animated ring around the cutout. Intensity bumps after 25s. -->
        <rect
          :x="cutoutRect.x - 3"
          :y="cutoutRect.y - 3"
          :width="cutoutRect.width + 6"
          :height="cutoutRect.height + 6"
          rx="17"
          ry="17"
          fill="none"
          stroke="url(#onboarding-spotlight-ring)"
          :stroke-width="intense ? 3.5 : 2"
          class="motion-safe:animate-pulse"
        />
      </svg>

      <!-- Animated cursor hand — points from the target toward the popover.
           Pure SVG so dark/light themes match without extra assets. -->
      <div
        v-if="entered && targetRect.width"
        aria-hidden="true"
        class="absolute pointer-events-none motion-safe:transition-all motion-safe:duration-500 motion-safe:ease-[cubic-bezier(0.16,1,0.3,1)]"
        :style="{
          top: `${pointerPos.top}px`,
          left: `${pointerPos.left}px`,
          transform: `rotate(${pointerPos.rotate}deg)`,
        }"
      >
        <span
          class="block size-7 rounded-full bg-gradient-to-br from-n-teal-9 to-n-teal-10 shadow-[0_8px_24px_-8px_rgba(19,203,141,0.7)] flex items-center justify-center motion-safe:animate-bounce"
        >
          <Icon icon="i-lucide-mouse-pointer-2" class="size-4 text-white" />
        </span>
      </div>

      <!-- Narrator popover — glass morph + chapter eyebrow + progress dots. -->
      <div
        class="absolute pointer-events-auto rounded-2xl border border-n-teal-7/40 bg-n-surface-1/85 backdrop-blur-2xl shadow-[0_24px_70px_-20px_rgba(0,0,0,0.55),0_0_0_1px_rgba(19,203,141,0.08)] motion-safe:transition-all motion-safe:duration-500 motion-safe:ease-[cubic-bezier(0.16,1,0.3,1)]"
        :class="popoverShiftClass"
        :style="{
          top: `${popoverPos.top}px`,
          left: `${popoverPos.left}px`,
          width: `${POPOVER_W}px`,
        }"
      >
        <div
          class="absolute inset-x-0 top-0 h-[3px] rounded-t-2xl bg-gradient-to-r from-n-teal-9 via-n-teal-10 to-n-teal-9"
        />
        <div class="p-5">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2 min-w-0">
              <span
                class="inline-flex items-center justify-center size-5 rounded-md bg-n-teal-9/15 text-n-teal-11 text-[10px] font-bold tabular-nums"
              >
                {{ step }}
              </span>
              <p
                v-if="chapter"
                class="text-[10.5px] font-bold uppercase tracking-[0.18em] text-n-teal-11 m-0 truncate"
              >
                {{ chapter }}
              </p>
              <p
                v-else
                class="text-[10.5px] font-bold uppercase tracking-[0.18em] text-n-teal-11 m-0"
              >
                {{ step }} / {{ total }}
              </p>
            </div>
            <button
              type="button"
              class="-mr-1 -mt-1 inline-flex items-center justify-center size-7 rounded-md text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2 transition-colors cursor-pointer"
              :aria-label="skipLabel"
              @click="emit('skip')"
            >
              <Icon icon="i-lucide-x" class="size-4" />
            </button>
          </div>
          <h3
            class="text-base font-semibold text-n-slate-12 m-0 mt-2 leading-snug tracking-tight"
          >
            {{ title }}
          </h3>
          <p class="text-[13px] text-n-slate-11 mt-2 m-0 leading-relaxed">
            {{ body }}
          </p>
          <p
            v-if="hint"
            class="mt-3 inline-flex items-center gap-1.5 rounded-md bg-n-teal-3/60 px-2 py-1 text-[11px] font-medium text-n-teal-12 m-0"
          >
            <Icon icon="i-lucide-mouse-pointer-click" class="size-3" />
            {{ hint }}
          </p>
          <div class="flex items-center gap-1.5 mt-4">
            <span
              v-for="d in total"
              :key="d"
              class="h-1 rounded-full transition-all duration-300"
              :class="
                d === step
                  ? 'bg-n-teal-9 w-5'
                  : d < step
                    ? 'bg-n-teal-9 w-1.5'
                    : 'bg-n-slate-5 w-1.5'
              "
            />
          </div>
          <div class="flex items-center justify-between gap-2 mt-5">
            <button
              type="button"
              class="text-xs font-medium text-n-slate-11 hover:text-n-slate-12 px-2 py-1 cursor-pointer transition-colors"
              @click="emit('skip')"
            >
              {{ skipLabel }}
            </button>
            <div class="flex items-center gap-1.5">
              <button
                v-if="step > 1"
                type="button"
                class="inline-flex items-center justify-center size-8 rounded-lg border border-n-weak text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2 cursor-pointer transition-colors"
                :aria-label="prevLabel"
                @click="emit('prev')"
              >
                <Icon icon="i-lucide-chevron-left" class="size-4" />
              </button>
              <button
                type="button"
                class="inline-flex items-center gap-1.5 px-3 h-8 rounded-lg bg-gradient-to-br from-n-teal-9 to-n-teal-10 text-white text-xs font-semibold shadow-md hover:shadow-lg hover:from-n-teal-10 hover:to-n-teal-9 cursor-pointer transition-all"
                @click="emit('next')"
              >
                {{ primaryLabel }}
                <Icon icon="i-lucide-arrow-right" class="size-3.5" />
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>
