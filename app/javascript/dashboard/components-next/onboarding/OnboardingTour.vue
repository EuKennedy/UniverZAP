<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useWindowSize } from '@vueuse/core';
import confetti from 'canvas-confetti';
import { emitter } from 'shared/helpers/mitt';
import { useAccount } from 'dashboard/composables/useAccount';
import { useOnboardingState } from 'dashboard/composables/useOnboardingState';
import {
  CONTEXTUAL_TOUR_KEYS,
  ONBOARDING_TOUR_EVENTS,
  buildTourSteps,
} from './onboardingSteps';
import OnboardingFullscreenStep from './OnboardingFullscreenStep.vue';
import OnboardingSpotlight from './OnboardingSpotlight.vue';

const { t } = useI18n();
const router = useRouter();
const { accountId } = useAccount();
const {
  flags,
  lastStepIndex,
  markTourCompleted,
  markContextualTourCompleted,
  refresh,
  setLastStepIndex,
} = useOnboardingState();
const { width: viewportWidth } = useWindowSize();

// Phones can't host a Floating UI-style popover next to a 200px target
// without overlap. Below 768px we lean entirely on the fullscreen step
// component so the storytelling stays intact.
const isMobileViewport = computed(() => viewportWidth.value < 768);

const isActive = ref(false);
const currentStepIndex = ref(0);
const currentTarget = ref(null);
const isFullscreen = ref(false);
// `null` for the main tour (default), or a contextual tour key like
// `conversation_view` while a mini-tour is mid-flight. Finishing a
// contextual tour writes to `onboarding_completed_tours` so the
// orchestrator doesn't re-fire it on the next visit.
const activeContextualKey = ref(null);
// Steps for the current tour (main tour by default, contextual otherwise).
// Stored in a ref so the contextual orchestrator can swap the catalogue
// without remounting the component.
const tourSteps = ref([]);

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

// Skip steps whose readiness flag is already satisfied — never make the
// user re-click a task they've finished. Recomputed reactively because
// flags can flip while the tour is mid-flight. Main tour reads from the
// authoritative catalogue; contextual tours skip the filter so the
// orchestrator can re-fire them deliberately.
const activeSteps = computed(() => {
  const isMain = activeContextualKey.value === null;
  return tourSteps.value.filter(step => {
    if (!isMain) return true;
    if (!step.requireFlag) return true;
    return !flags.value[step.requireFlag];
  });
});

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
  const contextualKey = activeContextualKey.value;
  teardown();
  if (contextualKey) {
    activeContextualKey.value = null;
    tourSteps.value = [];
    await markContextualTourCompleted(contextualKey);
    emitter.emit(ONBOARDING_TOUR_EVENTS.CONTEXTUAL_COMPLETED, {
      key: contextualKey,
    });
    return;
  }
  await setLastStepIndex(0);
  await markTourCompleted();
  // Main tour also counts as a contextual completion so the orchestrator
  // doesn't immediately re-fire one of the mini-tours on top of the
  // finish confetti.
  await markContextualTourCompleted(CONTEXTUAL_TOUR_KEYS.MAIN);
  await refresh({ force: true });
  emitter.emit(ONBOARDING_TOUR_EVENTS.COMPLETED);
  fireConfetti();
};

const exitTour = () => {
  const wasContextual = activeContextualKey.value !== null;
  const contextualKey = activeContextualKey.value;
  teardown();
  if (wasContextual) {
    activeContextualKey.value = null;
    tourSteps.value = [];
  }
  emitter.emit(ONBOARDING_TOUR_EVENTS.EXIT, {
    contextual: wasContextual,
    key: contextualKey,
  });
};

const goToStep = async index => {
  if (index < 0) return;
  currentStepIndex.value = index;
  // Only persist progress for the main tour — contextual tours are
  // ephemeral and rerun if the user explicitly resets them.
  if (activeContextualKey.value === null) {
    setLastStepIndex(index);
  }
  emitter.emit(ONBOARDING_TOUR_EVENTS.STEP_CHANGED, {
    index,
    total: activeSteps.value.length,
    contextual: activeContextualKey.value,
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

const startTour = async ({ restart = false } = {}) => {
  // Main tour entry — always pulls the canonical catalogue. `restart` forces
  // the journey to replay from step 0 (fired by the "?" help launcher); the
  // FAB/panel emit START with no payload and resume from `lastStepIndex`.
  activeContextualKey.value = null;
  tourSteps.value = buildTourSteps({ t });
  isActive.value = true;
  const resumeIndex = restart
    ? 0
    : Math.min(
        Math.max(lastStepIndex.value || 0, 0),
        Math.max(tourSteps.value.length - 1, 0)
      );
  await goToStep(resumeIndex);
};

// Contextual tour entry — orchestrator passes a tour key + steps array so
// we can reuse the same spotlight + popover surfaces without forking the
// component. Voice narration stays on the same opt-in setting.
const startContextualTour = async ({ key, steps }) => {
  if (!key || !Array.isArray(steps) || steps.length === 0) return;
  activeContextualKey.value = key;
  tourSteps.value = steps;
  isActive.value = true;
  await goToStep(0);
};

// Smart watcher: if a readiness flag flips true off-tour (e.g. the user
// added an inbox in another tab) skip past that step automatically. Only
// fires for the main tour — contextual flows don't have readiness gating.
watch(
  () => Object.values(flags.value).join('|'),
  () => {
    if (!isActive.value) return;
    if (activeContextualKey.value !== null) return;
    const step = currentStep.value;
    if (!step?.requireFlag) return;
    if (flags.value[step.requireFlag]) goToStep(currentStepIndex.value + 1);
  }
);

onMounted(() => {
  emitter.on(ONBOARDING_TOUR_EVENTS.START, startTour);
  emitter.on(ONBOARDING_TOUR_EVENTS.START_CONTEXTUAL, startContextualTour);
});
onBeforeUnmount(() => {
  emitter.off(ONBOARDING_TOUR_EVENTS.START, startTour);
  emitter.off(ONBOARDING_TOUR_EVENTS.START_CONTEXTUAL, startContextualTour);
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
