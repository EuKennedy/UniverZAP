<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { emitter } from 'shared/helpers/mitt';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useOnboardingState } from 'dashboard/composables/useOnboardingState';
import Icon from 'next/icon/Icon.vue';
import { ONBOARDING_TOUR_EVENTS } from './onboardingSteps';

// Persistent "?" help launcher. Unlike the rocket FAB (OnboardingLauncher),
// which self-hides once the account looks configured, this one is ALWAYS
// available so anyone can re-run the guided tour or jump to the docs. It's a
// thin trigger — the whole tour engine lives in OnboardingTour.vue and we
// just re-emit its START event with `{ restart: true }` so it replays from
// the very first chapter instead of resuming mid-way. Zero backend changes.

const { t } = useI18n();
const route = useRoute();
const { isAdmin } = useAdmin();
const {
  isComplete,
  explicitDismiss,
  isLoaded,
  tourCompletedAt,
  refresh,
  setLastStepIndex,
  resetDismiss,
} = useOnboardingState();

const isOpen = ref(false);

onMounted(() => {
  refresh();
});

// Mirror OnboardingLauncher's route guard: never overlay auth / setup flows.
const isHiddenRoute = computed(() => {
  const name = route.name || '';
  return /^(login|signup|reset|password|onboarding_setup)/.test(name);
});

// Admin-only, same as the rest of the onboarding surface — the guided tour
// walks through account-setup screens that agents can't reach anyway.
const isVisible = computed(() => isAdmin.value && !isHiddenRoute.value);

// Recompute the rocket FAB's visibility here so we can stack directly above
// it (bottom-36) while it is around, then drop into its slot (bottom-20)
// once the account graduates — keeps the FAB column gap-free. Mirrors the
// condition in OnboardingLauncher.isVisible (isAdmin/isHiddenRoute already
// gate this component, so we only need the readiness part).
const hasRegressed = computed(
  () => Boolean(tourCompletedAt.value) && !isComplete.value
);
const rocketShowing = computed(
  () =>
    isLoaded.value &&
    !(isComplete.value && !hasRegressed.value) &&
    !(explicitDismiss.value && !hasRegressed.value)
);

const toggle = () => {
  isOpen.value = !isOpen.value;
};
const close = () => {
  isOpen.value = false;
};

const retakeTour = async () => {
  close();
  // Reset the persisted resume pointer and clear any explicit dismiss so the
  // journey plays from step 0, then hand off to the tour engine.
  await setLastStepIndex(0);
  resetDismiss();
  emitter.emit(ONBOARDING_TOUR_EVENTS.START, { restart: true });
};

const openDocs = () => {
  close();
  // Same-origin docs page (Rails-rendered), opened in a new tab so we never
  // yank the operator out of the dashboard. Relative path keeps it correct
  // across staging / production without hardcoding a host.
  window.open('/docs', '_blank', 'noopener');
};
</script>

<template>
  <div v-if="isVisible">
    <!-- Click-catcher: closes the menu on any outside click. Sits below the
         launcher (z-40) so the button + popover (z-50) stay interactive. -->
    <div
      v-if="isOpen"
      class="fixed inset-0 z-40"
      aria-hidden="true"
      @click="close"
    />

    <div
      class="fixed ltr:right-4 rtl:left-4 z-50 transition-[bottom] duration-300 ease-[cubic-bezier(0.16,1,0.3,1)]"
      :class="rocketShowing ? 'bottom-36' : 'bottom-20'"
      data-onboarding="onboarding-help"
    >
      <Transition
        enter-active-class="motion-safe:transition-all motion-safe:duration-200 motion-safe:ease-[cubic-bezier(0.16,1,0.3,1)]"
        enter-from-class="opacity-0 translate-y-2 scale-95"
        enter-to-class="opacity-100 translate-y-0 scale-100"
        leave-active-class="motion-safe:transition-all motion-safe:duration-150 motion-safe:ease-in"
        leave-from-class="opacity-100"
        leave-to-class="opacity-0 translate-y-2 scale-95"
      >
        <div
          v-if="isOpen"
          class="absolute bottom-full mb-3 ltr:right-0 rtl:left-0 w-72 max-w-[calc(100vw-2rem)] origin-bottom-right overflow-hidden rounded-2xl border border-n-weak/70 bg-n-surface-1 shadow-[0_24px_70px_-20px_rgba(0,0,0,0.55),0_0_0_1px_rgba(19,203,141,0.08)]"
          role="menu"
          :aria-label="t('ONBOARDING_TOUR.HELP.ARIA_LABEL')"
        >
          <div
            class="px-4 pt-4 pb-3 border-b border-n-weak/60 bg-gradient-to-br from-n-teal-9/15 to-transparent"
          >
            <p class="m-0 text-sm font-semibold leading-tight text-n-slate-12">
              {{ t('ONBOARDING_TOUR.HELP.TITLE') }}
            </p>
            <p class="m-0 mt-0.5 text-xs leading-relaxed text-n-slate-11">
              {{ t('ONBOARDING_TOUR.HELP.SUBTITLE') }}
            </p>
          </div>
          <div class="p-1.5">
            <button
              type="button"
              role="menuitem"
              class="group flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left transition-colors duration-150 cursor-pointer hover:bg-n-alpha-2"
              @click="retakeTour"
            >
              <span
                class="inline-flex size-9 shrink-0 items-center justify-center rounded-lg bg-gradient-to-br from-n-teal-9 to-n-teal-10 text-white ring-1 ring-white/10"
              >
                <Icon icon="i-lucide-rotate-ccw" class="size-4" />
              </span>
              <span class="flex min-w-0 flex-col">
                <span class="text-sm font-medium leading-tight text-n-slate-12">
                  {{ t('ONBOARDING_TOUR.HELP.RETAKE_TOUR') }}
                </span>
                <span class="mt-0.5 text-xs leading-snug text-n-slate-11">
                  {{ t('ONBOARDING_TOUR.HELP.RETAKE_TOUR_DESC') }}
                </span>
              </span>
            </button>
            <button
              type="button"
              role="menuitem"
              class="group flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left transition-colors duration-150 cursor-pointer hover:bg-n-alpha-2"
              @click="openDocs"
            >
              <span
                class="inline-flex size-9 shrink-0 items-center justify-center rounded-lg bg-n-alpha-2 text-n-slate-11 ring-1 ring-n-weak/60 group-hover:text-n-slate-12"
              >
                <Icon icon="i-lucide-book-open" class="size-4" />
              </span>
              <span class="flex min-w-0 flex-1 flex-col">
                <span
                  class="inline-flex items-center gap-1 text-sm font-medium leading-tight text-n-slate-12"
                >
                  {{ t('ONBOARDING_TOUR.HELP.DOCS') }}
                  <Icon
                    icon="i-lucide-external-link"
                    class="size-3 text-n-slate-10"
                  />
                </span>
                <span class="mt-0.5 text-xs leading-snug text-n-slate-11">
                  {{ t('ONBOARDING_TOUR.HELP.DOCS_DESC') }}
                </span>
              </span>
            </button>
          </div>
        </div>
      </Transition>

      <!-- The persistent "?" button. Understated on purpose so it doesn't
           compete with the teal rocket / copilot FABs; brightens on hover. -->
      <button
        type="button"
        class="relative flex size-11 items-center justify-center rounded-full bg-n-solid-2 text-n-slate-11 shadow-lg ring-1 ring-n-weak backdrop-blur-sm transition-all duration-200 cursor-pointer hover:scale-105 hover:text-n-slate-12 hover:ring-n-teal-8 active:scale-95"
        :class="{ 'text-n-slate-12 ring-n-teal-8': isOpen }"
        :aria-label="t('ONBOARDING_TOUR.HELP.ARIA_LABEL')"
        :aria-expanded="isOpen"
        :title="t('ONBOARDING_TOUR.HELP.TOOLTIP')"
        @click="toggle"
      >
        <Icon icon="i-lucide-circle-help" class="size-5" />
      </button>
    </div>
  </div>
</template>
