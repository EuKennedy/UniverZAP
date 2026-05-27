<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useWindowSize } from '@vueuse/core';
import confetti from 'canvas-confetti';
import { emitter } from 'shared/helpers/mitt';
import { useAccount } from 'dashboard/composables/useAccount';
import { useOnboardingState } from 'dashboard/composables/useOnboardingState';
import { ONBOARDING_TOUR_EVENTS, buildTourSteps } from './onboardingSteps';
import OnboardingFullscreenStep from './OnboardingFullscreenStep.vue';
import OnboardingSpotlight from './OnboardingSpotlight.vue';

const { t } = useI18n();
const router = useRouter();
const { accountId } = useAccount();
const { flags, lastStepIndex, markTourCompleted, refresh, setLastStepIndex } =
  useOnboardingState();
const { width: viewportWidth } = useWindowSize();

// Phones can't host a Floating UI-style popover next to a 200px target
// without overlap. Below 768px we lean entirely on the fullscreen step
// component so the storytelling stays intact.
const isMobileViewport = computed(() => viewportWidth.value < 768);

const isActive = ref(false);
const currentStepIndex = ref(0);
const currentTarget = ref(null);
const isFullscreen = ref(false);

// Voice opt-in is persisted across sessions so the operator's preference
// sticks. Default is OFF — narration without explicit consent feels
// invasive.
const VOICE_LS_KEY = 'univerzap.onboarding.voice';
const voiceEnabled = ref(false);
try {
  voiceEnabled.value = window.localStorage.getItem(VOICE_LS_KEY) === '1';
} catch (_) {
  /* noop — SSR or privacy-mode storage */
}

const allSteps = computed(() => buildTourSteps({ t }));

// Skip steps whose readiness flag is already satisfied — never make the
// user re-click a task they've finished. Recomputed reactively because
// flags can flip while the tour is mid-flight.
const activeSteps = computed(() =>
  allSteps.value.filter(step => {
    if (!step.requireFlag) return true;
    return !flags.value[step.requireFlag];
  })
);

const currentStep = computed(
  () => activeSteps.value[currentStepIndex.value] || null
);

const waitForElement = (selector, timeout = 5000) =>
  new Promise(resolve => {
    const start = performance.now();
    const tick = () => {
      const el = document.querySelector(selector);
      if (el) return resolve(el);
      if (performance.now() - start > timeout) return resolve(null);
      return requestAnimationFrame(tick);
    };
    tick();
  });

// Per-step micro-celebration when the user actually clicks the target.
// Smaller than the full-blown finish burst — feels rewarding without
// breaking flow. Honors prefers-reduced-motion.
const fireMicroConfetti = anchor => {
  if (
    typeof window !== 'undefined' &&
    window.matchMedia('(prefers-reduced-motion: reduce)').matches
  ) {
    return;
  }
  const rect = anchor?.getBoundingClientRect?.();
  const x = rect ? (rect.left + rect.width / 2) / window.innerWidth : 0.5;
  const y = rect ? (rect.top + rect.height / 2) / window.innerHeight : 0.5;
  confetti({
    particleCount: 18,
    spread: 60,
    startVelocity: 30,
    gravity: 1.2,
    scalar: 0.7,
    ticks: 70,
    origin: { x, y },
    colors: ['#13CB8D', '#60E8B8', '#0FA873'],
  });
};

const fireConfetti = () => {
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  const colors = ['#13CB8D', '#60E8B8', '#0FA873', '#f1f5f4'];
  const end = Date.now() + 1500;
  (function frame() {
    confetti({
      particleCount: 4,
      angle: 60,
      spread: 70,
      origin: { x: 0, y: 0.7 },
      colors,
    });
    confetti({
      particleCount: 4,
      angle: 120,
      spread: 70,
      origin: { x: 1, y: 0.7 },
      colors,
    });
    if (Date.now() < end) requestAnimationFrame(frame);
  })();
};

// Tailwind utility classes layered on the live target during a step so it
// pops above the dark backdrop. Adds transition first, then the visual
// classes on the next frame so the browser animates the change instead
// of snapping to the new state.
const FOCUS_TRANSITION_CLASSES = [
  'motion-safe:transition-all',
  'motion-safe:duration-500',
  'motion-safe:ease-[cubic-bezier(0.16,1,0.3,1)]',
];
const FOCUS_VISUAL_CLASSES = [
  'ring-4',
  'ring-n-teal-9/60',
  'shadow-2xl',
  'shadow-n-teal-9/30',
  'rounded-xl',
  'scale-[1.02]',
];

let lastFocusedEl = null;
const removeTargetFocus = el => {
  if (!el) return;
  el.classList.remove(...FOCUS_VISUAL_CLASSES);
  window.setTimeout(() => {
    el.classList.remove(...FOCUS_TRANSITION_CLASSES);
  }, 500);
};
const applyTargetFocus = el => {
  if (!el) return;
  el.classList.add(...FOCUS_TRANSITION_CLASSES);
  requestAnimationFrame(() => {
    el.classList.add(...FOCUS_VISUAL_CLASSES);
  });
};

watch(currentTarget, (next, prev) => {
  if (prev && prev !== next) removeTargetFocus(prev);
  if (next) {
    lastFocusedEl = next;
    applyTargetFocus(next);
  } else {
    lastFocusedEl = null;
  }
});

const teardown = () => {
  if (lastFocusedEl) removeTargetFocus(lastFocusedEl);
  lastFocusedEl = null;
  isActive.value = false;
  currentTarget.value = null;
  isFullscreen.value = false;
};

const finishTour = async () => {
  teardown();
  await setLastStepIndex(0);
  await markTourCompleted();
  await refresh({ force: true });
  emitter.emit(ONBOARDING_TOUR_EVENTS.COMPLETED);
  fireConfetti();
};

const exitTour = () => {
  teardown();
  emitter.emit(ONBOARDING_TOUR_EVENTS.EXIT);
};

const goToStep = async index => {
  if (index < 0) return;
  currentStepIndex.value = index;
  setLastStepIndex(index);
  emitter.emit(ONBOARDING_TOUR_EVENTS.STEP_CHANGED, {
    index,
    total: activeSteps.value.length,
  });

  if (index >= activeSteps.value.length) {
    await finishTour();
    return;
  }

  const step = activeSteps.value[index];

  // Fullscreen branch — welcome/finish steps, plus everything on mobile.
  if (step.fullscreen || isMobileViewport.value) {
    isFullscreen.value = true;
    currentTarget.value = null;
    if (step.navigateTo) {
      const target = step.navigateTo(accountId.value);
      if (router.currentRoute.value.name !== target.name) {
        await router.push(target);
      }
    }
    return;
  }

  isFullscreen.value = false;

  if (step.navigateTo) {
    const target = step.navigateTo(accountId.value);
    if (router.currentRoute.value.name !== target.name) {
      await router.push(target);
    }
  }

  // Try the canonical `data-onboarding` attribute first, then fall back to
  // any selectors the step declared. The fallback list lets enterprise
  // overlays or A/B variants ship a different DOM without breaking the
  // tour.
  const candidates = [
    step.dataOnboarding && `[data-onboarding="${step.dataOnboarding}"]`,
    ...(step.selectors || []),
  ].filter(Boolean);
  // Sequential fallback chain — we *want* to await each candidate in order
  // before trying the next so the canonical selector wins when present.
  // Using a counter-driven while keeps the airbnb `no-restricted-syntax`
  // (no for-of) and `no-await-in-loop` rules happy via inline disable.
  let element = null;
  let idx = 0;
  while (idx < candidates.length && !element) {
    // eslint-disable-next-line no-await-in-loop
    element = await waitForElement(candidates[idx], 8000);
    idx += 1;
  }
  if (!element) {
    // Target never appeared — gracefully advance instead of breaking the tour.
    await goToStep(index + 1);
    return;
  }
  currentTarget.value = element;
};

const handleNext = () => goToStep(currentStepIndex.value + 1);
const handlePrev = () => goToStep(Math.max(0, currentStepIndex.value - 1));
const handleSkip = () => exitTour();

// User actually clicked the highlighted target — let the UI react for a
// beat, fire a small celebration, then advance. This is the "do it once,
// learn forever" pattern ClickUp / Stripe Atlas use.
const handleTargetClick = () => {
  const idx = currentStepIndex.value;
  fireMicroConfetti(currentTarget.value);
  setTimeout(() => {
    if (currentStepIndex.value === idx) goToStep(idx + 1);
  }, 650);
};

const toggleVoice = () => {
  voiceEnabled.value = !voiceEnabled.value;
  try {
    window.localStorage.setItem(VOICE_LS_KEY, voiceEnabled.value ? '1' : '0');
  } catch (_) {
    /* noop */
  }
};

const startTour = async () => {
  isActive.value = true;
  const resumeIndex = Math.min(
    Math.max(lastStepIndex.value || 0, 0),
    Math.max(activeSteps.value.length - 1, 0)
  );
  await goToStep(resumeIndex);
};

// Smart watcher: if a readiness flag flips true off-tour (e.g. the user
// added an inbox in another tab) skip past that step automatically.
watch(
  () => Object.values(flags.value).join('|'),
  () => {
    if (!isActive.value) return;
    const step = currentStep.value;
    if (!step?.requireFlag) return;
    if (flags.value[step.requireFlag]) goToStep(currentStepIndex.value + 1);
  }
);

onMounted(() => {
  emitter.on(ONBOARDING_TOUR_EVENTS.START, startTour);
});
onBeforeUnmount(() => {
  emitter.off(ONBOARDING_TOUR_EVENTS.START, startTour);
  teardown();
});
</script>

<template>
  <OnboardingSpotlight
    v-if="isActive && currentTarget && !isFullscreen && currentStep"
    :target="currentTarget"
    :title="currentStep.title"
    :body="currentStep.body"
    :chapter="currentStep.chapter || ''"
    :side="currentStep.side || 'right'"
    :step="currentStepIndex + 1"
    :total="activeSteps.length"
    :primary-label="t('ONBOARDING_TOUR.TOUR.NEXT')"
    :prev-label="t('ONBOARDING_TOUR.TOUR.PREVIOUS')"
    :skip-label="t('ONBOARDING_TOUR.TOUR.SKIP')"
    :voice-enabled="voiceEnabled"
    :hint="
      currentStep.clickToAdvance ? t('ONBOARDING_TOUR.TOUR.CLICK_HINT') : ''
    "
    @next="handleNext"
    @prev="handlePrev"
    @skip="handleSkip"
    @target-click="currentStep.clickToAdvance ? handleTargetClick() : null"
  />
  <OnboardingFullscreenStep
    v-if="isActive && isFullscreen && currentStep"
    :title="currentStep.title"
    :body="currentStep.body"
    :primary-label="currentStep.primaryLabel || t('ONBOARDING_TOUR.TOUR.NEXT')"
    :secondary-label="
      currentStep.secondaryLabel || t('ONBOARDING_TOUR.TOUR.SKIP')
    "
    :step="currentStepIndex + 1"
    :total="activeSteps.length"
    :chapter="currentStep.chapter || ''"
    :voice-enabled="voiceEnabled"
    @primary="handleNext"
    @secondary="handleSkip"
    @toggle-voice="toggleVoice"
  />
</template>
