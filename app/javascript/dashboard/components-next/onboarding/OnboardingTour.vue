<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useWindowSize } from '@vueuse/core';
import { driver } from 'driver.js';
import 'driver.js/dist/driver.css';
import confetti from 'canvas-confetti';
import { emitter } from 'shared/helpers/mitt';
import { useAccount } from 'dashboard/composables/useAccount';
import { useOnboardingState } from 'dashboard/composables/useOnboardingState';
import { ONBOARDING_TOUR_EVENTS, buildTourSteps } from './onboardingSteps';
import OnboardingFullscreenStep from './OnboardingFullscreenStep.vue';

const { t } = useI18n();
const router = useRouter();
const { accountId } = useAccount();
const { flags, lastStepIndex, markTourCompleted, refresh, setLastStepIndex } =
  useOnboardingState();
const { width: viewportWidth } = useWindowSize();

// Mobile spotlights from driver.js are unreliable on narrow viewports — the
// popover collides with the highlighted target. Fall back to a fullscreen
// step on phones (< 768px) so we keep the storytelling intact.
const isMobileViewport = computed(() => viewportWidth.value < 768);

// Engine state
const driverInstance = ref(null);
const isFullscreenStep = ref(false);
const currentStepConfig = ref(null);
const currentStepIndex = ref(0);

const allSteps = computed(() => buildTourSteps({ t }));

// Skip steps whose readiness flag is already satisfied — never make the user
// re-click a task they've already done. This is recomputed each step entry
// because the user may finish a task mid-tour (e.g. add an inbox).
const activeSteps = computed(() =>
  allSteps.value.filter(step => {
    if (!step.requireFlag) return true;
    return !flags.value[step.requireFlag];
  })
);

// Wait for a selector to appear in the DOM after navigation. Driver.js
// will try to anchor immediately; if the target isn't mounted yet, the
// spotlight misfires. We poll with rAF + a 5s ceiling.
const waitForElement = (selector, timeout = 5000) => {
  return new Promise(resolve => {
    const start = performance.now();
    const tick = () => {
      const el = document.querySelector(selector);
      if (el) {
        resolve(el);
        return;
      }
      if (performance.now() - start > timeout) {
        resolve(null);
        return;
      }
      requestAnimationFrame(tick);
    };
    tick();
  });
};

const fireConfetti = () => {
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (reduced) return;
  const duration = 1500;
  const end = Date.now() + duration;
  const colors = ['#13CB8D', '#60E8B8', '#0FA873', '#f1f5f4'];
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

const cleanupDriver = () => {
  if (driverInstance.value) {
    driverInstance.value.destroy();
    driverInstance.value = null;
  }
};

const handleFinish = async () => {
  cleanupDriver();
  isFullscreenStep.value = false;
  currentStepConfig.value = null;
  await setLastStepIndex(0);
  await markTourCompleted();
  await refresh({ force: true });
  emitter.emit(ONBOARDING_TOUR_EVENTS.COMPLETED);
  fireConfetti();
};

const handleExit = () => {
  cleanupDriver();
  isFullscreenStep.value = false;
  currentStepConfig.value = null;
  emitter.emit(ONBOARDING_TOUR_EVENTS.EXIT);
};

// Hand off control to the next step. If the next step is a fullscreen
// (welcome/finish) one, we render it ourselves and pause the driver. If it's
// an anchored step, we navigate first (if needed), wait for the target, then
// move the driver to it.
const goToStep = async index => {
  currentStepIndex.value = index;
  setLastStepIndex(index);
  emitter.emit(ONBOARDING_TOUR_EVENTS.STEP_CHANGED, {
    index,
    total: activeSteps.value.length,
  });

  if (index >= activeSteps.value.length) {
    await handleFinish();
    return;
  }
  const step = activeSteps.value[index];
  currentStepConfig.value = step;

  // Fullscreen branch covers welcome/finish steps and any anchored step on
  // mobile, where the driver.js popover would collide with the target.
  if (step.fullscreen || isMobileViewport.value) {
    isFullscreenStep.value = true;
    cleanupDriver();
    if (step.navigateTo) {
      const target = step.navigateTo(accountId.value);
      if (router.currentRoute.value.name !== target.name) {
        await router.push(target);
      }
    }
    return;
  }

  isFullscreenStep.value = false;

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

  cleanupDriver();
  driverInstance.value = driver({
    showProgress: false,
    showButtons: ['next', 'previous', 'close'],
    nextBtnText: t('ONBOARDING_TOUR.TOUR.NEXT'),
    prevBtnText: t('ONBOARDING_TOUR.TOUR.PREVIOUS'),
    doneBtnText: t('ONBOARDING_TOUR.TOUR.DONE'),
    popoverClass: 'univerzap-tour-popover',
    overlayColor: '#020617',
    overlayOpacity: 0.7,
    stagePadding: 8,
    stageRadius: 12,
    disableActiveInteraction: false,
    allowKeyboardControl: true,
    onPopoverRender: popover => {
      const progress = document.createElement('div');
      progress.className = 'univerzap-tour-progress';
      progress.textContent = t('ONBOARDING_TOUR.TOUR.STEP_PROGRESS', {
        current: index + 1,
        total: activeSteps.value.length,
      });
      popover.wrapper.insertBefore(progress, popover.wrapper.firstChild);
    },
    onCloseClick: handleExit,
    onDestroyStarted: () => {
      // Only treat user-initiated close as exit. Programmatic destroy from
      // goToStep() sets driverInstance to null before triggering this.
      if (driverInstance.value) handleExit();
    },
    steps: [
      {
        element,
        popover: {
          title: step.title,
          description: step.body,
          side: step.side || 'right',
          align: step.align || 'start',
          showButtons: ['next', 'close'],
          onNextClick: () => goToStep(index + 1),
          onCloseClick: handleExit,
        },
      },
    ],
  });
  driverInstance.value.drive();
};

const startTour = async () => {
  // Resume where the user left off — but never beyond the available steps
  // (active list shrinks as readiness flags flip).
  const resumeIndex = Math.min(
    Math.max(lastStepIndex.value || 0, 0),
    Math.max(activeSteps.value.length - 1, 0)
  );
  currentStepIndex.value = resumeIndex;
  await goToStep(resumeIndex);
};

const handlePrimary = () => {
  goToStep(currentStepIndex.value + 1);
};

const handleSecondary = () => {
  // Welcome step "skip" = exit; Finish step has no secondary.
  handleExit();
};

onMounted(() => {
  emitter.on(ONBOARDING_TOUR_EVENTS.START, startTour);
});
onBeforeUnmount(() => {
  emitter.off(ONBOARDING_TOUR_EVENTS.START, startTour);
  cleanupDriver();
});
</script>

<template>
  <OnboardingFullscreenStep
    v-if="isFullscreenStep && currentStepConfig"
    :title="currentStepConfig.title"
    :body="currentStepConfig.body"
    :primary-label="currentStepConfig.primaryLabel"
    :secondary-label="currentStepConfig.secondaryLabel"
    :step="currentStepIndex + 1"
    :total="activeSteps.length"
    @primary="handlePrimary"
    @secondary="handleSecondary"
  />
</template>

<style>
/* Driver.js theme override — match our dopamine/dark palette. Loaded
   globally (no scoped) because driver mounts its popover at body root. */
.univerzap-tour-popover {
  background: rgb(20 27 26) !important;
  border: 1px solid rgba(19, 203, 141, 0.35) !important;
  border-radius: 16px !important;
  box-shadow:
    0 24px 60px -20px rgba(0, 0, 0, 0.7),
    0 0 0 1px rgba(19, 203, 141, 0.15) !important;
  color: #f1f5f4 !important;
  padding: 18px 20px !important;
  max-width: 360px !important;
}
.univerzap-tour-popover .driver-popover-title {
  color: #f1f5f4 !important;
  font-size: 15px !important;
  font-weight: 600 !important;
  letter-spacing: -0.01em !important;
  margin-bottom: 6px !important;
}
.univerzap-tour-popover .driver-popover-description {
  color: #94a3b8 !important;
  font-size: 13px !important;
  line-height: 1.55 !important;
}
.univerzap-tour-popover .driver-popover-footer {
  margin-top: 16px !important;
  gap: 8px !important;
  display: flex !important;
  justify-content: flex-end !important;
}
.univerzap-tour-popover .driver-popover-progress-text {
  display: none !important;
}
.univerzap-tour-popover .driver-popover-prev-btn,
.univerzap-tour-popover .driver-popover-next-btn,
.univerzap-tour-popover .driver-popover-close-btn {
  border-radius: 10px !important;
  font-weight: 600 !important;
  font-size: 12px !important;
  padding: 8px 14px !important;
  letter-spacing: 0.01em !important;
  cursor: pointer;
  transition:
    transform 0.12s ease,
    box-shadow 0.15s ease;
}
.univerzap-tour-popover .driver-popover-next-btn {
  background: linear-gradient(135deg, #13CB8D, #0FA873) !important;
  color: #062E20 !important;
  border: none !important;
  text-shadow: none !important;
}
.univerzap-tour-popover .driver-popover-next-btn:hover {
  transform: translateY(-1px);
  box-shadow: 0 8px 24px -8px rgba(19, 203, 141, 0.55) !important;
}
.univerzap-tour-popover .driver-popover-prev-btn {
  background: transparent !important;
  color: #94a3b8 !important;
  border: 1px solid rgba(148, 163, 184, 0.25) !important;
}
.univerzap-tour-popover .driver-popover-close-btn {
  position: absolute !important;
  top: 12px !important;
  right: 12px !important;
  background: transparent !important;
  color: #64748b !important;
  border: none !important;
  padding: 4px !important;
  font-size: 18px !important;
  line-height: 1 !important;
}
.univerzap-tour-popover .driver-popover-close-btn:hover {
  color: #f1f5f4 !important;
}
.univerzap-tour-popover .driver-popover-arrow {
  border-color: rgba(20, 27, 26, 0.95) !important;
}
.univerzap-tour-progress {
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  color: #13CB8D;
  margin-bottom: 8px;
}
</style>
