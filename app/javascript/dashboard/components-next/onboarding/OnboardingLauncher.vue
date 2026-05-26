<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useOnboardingState } from 'dashboard/composables/useOnboardingState';
import Icon from 'next/icon/Icon.vue';
import OnboardingPanel from './OnboardingPanel.vue';

const { t } = useI18n();
const route = useRoute();
const { isAdmin } = useAdmin();
const {
  score,
  isComplete,
  isFresh,
  isLoaded,
  tourCompletedAt,
  explicitDismiss,
  refresh,
  resetDismiss,
  dismissExplicit,
} = useOnboardingState();

const isPanelOpen = ref(false);

onMounted(() => {
  refresh();
});

// Routes where the floating launcher must hide (auth pages, the magic-link
// setup screen). The tour itself manages mount/unmount.
const isHiddenRoute = computed(() => {
  const name = route.name || '';
  return /^(login|signup|reset|password|onboarding_setup)/.test(name);
});

const hasRegressed = computed(
  () => Boolean(tourCompletedAt.value) && !isComplete.value
);

// Auto-clear an old explicit-dismiss whenever readiness regresses — the
// user needs another nudge to finish what they undid.
watch(hasRegressed, regressed => {
  if (regressed && explicitDismiss.value) resetDismiss();
});

const isVisible = computed(() => {
  if (!isAdmin.value) return false;
  if (isHiddenRoute.value) return false;
  // Avoid the initial flash: don't render until the backend has answered
  // at least once. Otherwise score defaults to 0/5 and the FAB flickers in.
  if (!isLoaded.value) return false;
  if (isComplete.value && !hasRegressed.value) return false;
  if (explicitDismiss.value && !hasRegressed.value) return false;
  return true;
});

// Only pulse for genuinely fresh accounts — once anything is configured
// we stop the animation so the FAB doesn't keep "spamming" the user.
const shouldPulse = computed(() => isLoaded.value && isFresh.value);

// SVG progress ring around the rocket FAB. r=26 → C ≈ 163.36. We round
// to one decimal so the dash math stays stable across renders.
const RING_RADIUS = 26;
const RING_CIRCUMFERENCE = +(2 * Math.PI * RING_RADIUS).toFixed(2);
const progressPercent = computed(() =>
  score.value.total ? score.value.done / score.value.total : 0
);
const ringDashOffset = computed(
  () => +(RING_CIRCUMFERENCE * (1 - progressPercent.value)).toFixed(2)
);

const togglePanel = () => {
  isPanelOpen.value = !isPanelOpen.value;
  if (isPanelOpen.value) refresh({ force: true });
};
const closePanel = () => {
  isPanelOpen.value = false;
};

// One-click dismiss from the FAB itself. Doesn't open the panel, just
// sets onboarding_explicit_dismiss=true. The launcher will reappear
// only if the account's readiness regresses (auto-clear above).
const dismissFromFab = async event => {
  event.stopPropagation();
  await dismissExplicit();
};
</script>

<template>
  <div v-if="isVisible" data-onboarding="onboarding-launcher">
    <Transition
      enter-active-class="motion-safe:transition-all motion-safe:duration-500 motion-safe:ease-[cubic-bezier(0.16,1,0.3,1)]"
      enter-from-class="opacity-0 scale-50 translate-y-3"
      enter-to-class="opacity-100 scale-100 translate-y-0"
      leave-active-class="motion-safe:transition-all motion-safe:duration-150 motion-safe:ease-in"
      leave-from-class="opacity-100 scale-100"
      leave-to-class="opacity-0 scale-90"
    >
      <div
        v-if="!isPanelOpen"
        class="fixed bottom-20 ltr:right-4 rtl:left-4 z-50 group"
      >
        <!-- Aurora glow — diffuse gradient that wakes the FAB up on a dark
             dashboard without competing with the copilot button below. -->
        <span
          class="absolute -inset-3 rounded-full bg-gradient-to-tr from-n-teal-9 via-n-teal-10 to-n-violet-9 opacity-40 blur-xl motion-safe:animate-pulse pointer-events-none"
          aria-hidden="true"
        />

        <!-- Pulse ring only while the account is genuinely fresh and the
             readiness payload has actually loaded. -->
        <span
          v-if="shouldPulse"
          class="absolute inset-0 rounded-full bg-n-teal-9/40 motion-safe:animate-ping pointer-events-none"
          aria-hidden="true"
        />

        <!-- One-click dismiss — sets onboarding_explicit_dismiss without
             going through the panel. Revealed on hover so the FAB stays
             clean at rest. -->
        <button
          type="button"
          class="absolute -top-1.5 -left-1.5 z-20 inline-flex items-center justify-center size-6 rounded-full bg-n-slate-12 dark:bg-n-solid-2 text-white ring-2 ring-n-surface-1 opacity-0 group-hover:opacity-100 transition-opacity duration-150 cursor-pointer hover:bg-n-ruby-9"
          :aria-label="t('ONBOARDING_TOUR.LAUNCHER.DISMISS')"
          :title="t('ONBOARDING_TOUR.LAUNCHER.DISMISS')"
          @click="dismissFromFab"
        >
          <Icon icon="i-lucide-x" class="size-3.5" />
        </button>

        <!-- SVG progress ring wraps the rocket button. Track + colored arc.
             stroke-dasharray drives the percentage — same numbers feed the
             count badge so they're never out of sync. -->
        <svg
          class="absolute inset-0 -rotate-90 pointer-events-none"
          width="56"
          height="56"
          viewBox="0 0 56 56"
          aria-hidden="true"
        >
          <circle
            cx="28"
            cy="28"
            :r="RING_RADIUS"
            fill="none"
            stroke="rgb(255 255 255 / 0.18)"
            stroke-width="2.5"
          />
          <circle
            cx="28"
            cy="28"
            :r="RING_RADIUS"
            fill="none"
            stroke="white"
            stroke-width="2.5"
            stroke-linecap="round"
            :stroke-dasharray="RING_CIRCUMFERENCE"
            :stroke-dashoffset="ringDashOffset"
            class="motion-safe:transition-[stroke-dashoffset] motion-safe:duration-700 motion-safe:ease-[cubic-bezier(0.16,1,0.3,1)]"
          />
        </svg>

        <!-- Main FAB — solid brand teal with a soft inner highlight so the
             icon doesn't feel pasted on. -->
        <button
          type="button"
          class="relative flex items-center justify-center size-14 rounded-full bg-gradient-to-br from-n-teal-9 to-n-teal-10 text-white shadow-xl ring-1 ring-n-teal-10/60 transition-all duration-200 group-hover:scale-105 group-hover:shadow-2xl group-active:scale-95 cursor-pointer"
          :aria-label="t('ONBOARDING_TOUR.LAUNCHER.ARIA_LABEL')"
          @click="togglePanel"
        >
          <Icon icon="i-lucide-rocket" class="size-6 drop-shadow-sm" />
          <span
            class="absolute -top-1 -right-1 min-w-5 h-5 px-1 inline-flex items-center justify-center rounded-full bg-n-slate-12 dark:bg-white text-n-slate-1 dark:text-n-slate-12 text-[10px] font-bold ring-2 ring-n-surface-1"
          >
            {{ score.done }}/{{ score.total }}
          </span>
        </button>

        <!-- Tooltip — uses the same brand teal accent and only renders on
             hover so the FAB stays uncluttered for power users. -->
        <span
          class="absolute right-full top-1/2 -translate-y-1/2 mr-3 whitespace-nowrap rounded-md bg-n-slate-12 dark:bg-white px-2.5 py-1.5 text-xs font-medium text-white dark:text-n-slate-12 opacity-0 group-hover:opacity-100 transition-opacity duration-200 pointer-events-none shadow-lg"
        >
          {{ t('ONBOARDING_TOUR.LAUNCHER.PULSE_HINT') }}
        </span>
      </div>
    </Transition>

    <Transition
      enter-active-class="motion-safe:transition-all motion-safe:duration-300 motion-safe:ease-[cubic-bezier(0.16,1,0.3,1)]"
      enter-from-class="opacity-0 translate-y-3 scale-95"
      enter-to-class="opacity-100 translate-y-0 scale-100"
      leave-active-class="motion-safe:transition-all motion-safe:duration-200 motion-safe:ease-in"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0 translate-y-3 scale-95"
    >
      <OnboardingPanel v-if="isPanelOpen" @close="closePanel" />
    </Transition>
  </div>
</template>
