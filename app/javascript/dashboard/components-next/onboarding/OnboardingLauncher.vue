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
  tourCompletedAt,
  explicitDismiss,
  refresh,
  resetDismiss,
} = useOnboardingState();

const isPanelOpen = ref(false);

onMounted(() => {
  refresh();
});

// Routes where the floating launcher must hide (auth pages, the tour overlay
// itself, the magic-link setup screen). The tour itself manages mount/unmount.
const isHiddenRoute = computed(() => {
  const name = route.name || '';
  return /^(login|signup|reset|password|onboarding_setup)/.test(name);
});

const hasRegressed = computed(
  () => Boolean(tourCompletedAt.value) && !isComplete.value
);

// Auto-clear an old explicit-dismiss whenever readiness regresses — the user
// needs another nudge to finish what they undid.
watch(hasRegressed, regressed => {
  if (regressed && explicitDismiss.value) resetDismiss();
});

const isVisible = computed(() => {
  if (!isAdmin.value) return false;
  if (isHiddenRoute.value) return false;
  if (isComplete.value && !hasRegressed.value) return false;
  if (explicitDismiss.value && !hasRegressed.value) return false;
  return true;
});

const togglePanel = () => {
  isPanelOpen.value = !isPanelOpen.value;
  // Re-fetch each time the user opens — readiness flags can change fast
  // when they finish a task in another tab.
  if (isPanelOpen.value) refresh({ force: true });
};
const closePanel = () => {
  isPanelOpen.value = false;
};
</script>

<template>
  <div v-if="isVisible" data-onboarding="onboarding-launcher">
    <Transition
      enter-active-class="transition duration-200 ease-out"
      enter-from-class="opacity-0 scale-90"
      enter-to-class="opacity-100 scale-100"
      leave-active-class="transition duration-150 ease-in"
      leave-from-class="opacity-100 scale-100"
      leave-to-class="opacity-0 scale-90"
    >
      <button
        v-if="!isPanelOpen"
        type="button"
        class="fixed bottom-20 ltr:right-4 rtl:left-4 z-50 group"
        :aria-label="t('ONBOARDING_TOUR.LAUNCHER.ARIA_LABEL')"
        @click="togglePanel"
      >
        <span
          v-if="isFresh"
          class="absolute inset-0 rounded-full bg-n-teal-9/40 motion-safe:animate-ping"
          aria-hidden="true"
        />
        <span
          class="relative flex items-center justify-center size-14 rounded-full bg-gradient-to-br from-n-teal-9 to-n-teal-10 text-white shadow-xl ring-1 ring-n-teal-11/50 transition-all duration-200 group-hover:scale-105 group-hover:shadow-2xl group-active:scale-95 cursor-pointer"
        >
          <Icon icon="i-lucide-rocket" class="size-6" />
          <span
            class="absolute -top-1 -right-1 min-w-5 h-5 px-1 inline-flex items-center justify-center rounded-full bg-n-slate-12 dark:bg-white text-n-slate-1 dark:text-n-slate-12 text-[10px] font-bold ring-2 ring-n-surface-1"
          >
            {{ score.done }}/{{ score.total }}
          </span>
        </span>
        <span
          class="absolute right-full top-1/2 -translate-y-1/2 mr-3 whitespace-nowrap rounded-md bg-n-slate-12 dark:bg-white px-2.5 py-1.5 text-xs font-medium text-white dark:text-n-slate-12 opacity-0 group-hover:opacity-100 transition-opacity duration-200 pointer-events-none shadow-lg"
        >
          {{ t('ONBOARDING_TOUR.LAUNCHER.PULSE_HINT') }}
        </span>
      </button>
    </Transition>

    <OnboardingPanel v-if="isPanelOpen" @close="closePanel" />
  </div>
</template>
