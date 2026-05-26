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
// "stage" around the target. Pop-over floats next to the cutout and
// flips to keep itself on-screen. Built so the tour feels like ClickUp /
// Stripe Atlas: dark backdrop, smooth zoom-in, pulse halo, target-click
// auto-advance, keyboard nav (← → Esc).
const props = defineProps({
  target: { type: Object, required: true },
  title: { type: String, required: true },
  body: { type: String, required: true },
  side: { type: String, default: 'right' },
  step: { type: Number, default: 1 },
  total: { type: Number, default: 1 },
  primaryLabel: { type: String, required: true },
  prevLabel: { type: String, required: true },
  skipLabel: { type: String, required: true },
  hint: { type: String, default: '' },
});

const emit = defineEmits(['next', 'prev', 'skip', 'targetClick']);

const { width: vw, height: vh } = useWindowSize();

const PAD_REST = 10;
const PAD_ZOOM = 36;
const POPOVER_W = 360;
const POPOVER_H_ESTIMATE = 220;

const targetRect = ref({ top: 0, left: 0, width: 0, height: 0 });
const entered = ref(false);

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
  const pad = entered.value ? PAD_REST : PAD_ZOOM;
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
  const gap = 18;
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

const handleDocClick = event => {
  if (props.target?.contains?.(event.target)) {
    emit('targetClick');
  }
};

const handleKey = event => {
  if (event.key === 'Escape') {
    emit('skip');
  } else if (event.key === 'ArrowRight' || event.key === 'Enter') {
    emit('next');
  } else if (event.key === 'ArrowLeft') {
    emit('prev');
  }
};

watch(
  () => props.target,
  () => {
    entered.value = false;
    recompute();
    nextTick(() => {
      requestAnimationFrame(() => {
        entered.value = true;
      });
    });
  }
);

onMounted(() => {
  recompute();
  props.target?.scrollIntoView?.({ block: 'center', behavior: 'smooth' });
  // Two-frame wait so the scrollIntoView animation has time to settle before
  // we measure — otherwise the cutout briefly anchors to the pre-scroll rect.
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
});

onBeforeUnmount(() => {
  window.removeEventListener('resize', recompute);
  window.removeEventListener('scroll', recompute, true);
  document.removeEventListener('click', handleDocClick, true);
  document.removeEventListener('keydown', handleKey);
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
        </defs>
        <rect
          :width="vw"
          :height="vh"
          fill="rgb(2 6 23 / 0.82)"
          mask="url(#onboarding-spotlight-mask)"
        />
        <rect
          :x="cutoutRect.x - 3"
          :y="cutoutRect.y - 3"
          :width="cutoutRect.width + 6"
          :height="cutoutRect.height + 6"
          rx="17"
          ry="17"
          fill="none"
          stroke="url(#onboarding-spotlight-ring)"
          stroke-width="2"
          class="motion-safe:animate-pulse"
        />
      </svg>
      <div
        class="absolute pointer-events-auto rounded-2xl border border-n-teal-7/40 bg-n-surface-1 shadow-2xl motion-safe:transition-all motion-safe:duration-500 motion-safe:ease-[cubic-bezier(0.16,1,0.3,1)]"
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
            <p
              class="text-[10.5px] font-bold uppercase tracking-[0.18em] text-n-teal-11 m-0"
            >
              {{ step }} / {{ total }}
            </p>
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
