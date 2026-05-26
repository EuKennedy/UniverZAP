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

const teardown = () => {
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

  const selector = `[data-onboarding="${step.dataOnboarding}"]`;
  const element = await waitForElement(selector, 10000);
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
// beat, then advance. This is the "do it once, learn forever" pattern
// ClickUp / Stripe Atlas use.
const handleTargetClick = () => {
  const idx = currentStepIndex.value;
  setTimeout(() => {
    if (currentStepIndex.value === idx) goToStep(idx + 1);
  }, 650);
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
    :side="currentStep.side || 'right'"
    :step="currentStepIndex + 1"
    :total="activeSteps.length"
    :primary-label="t('ONBOARDING_TOUR.TOUR.NEXT')"
    :prev-label="t('ONBOARDING_TOUR.TOUR.PREVIOUS')"
    :skip-label="t('ONBOARDING_TOUR.TOUR.SKIP')"
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
    @primary="handleNext"
    @secondary="handleSkip"
  />
</template>
