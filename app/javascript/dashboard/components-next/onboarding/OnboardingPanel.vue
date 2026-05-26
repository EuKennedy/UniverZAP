<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useOnboardingState } from 'dashboard/composables/useOnboardingState';
import { emitter } from 'shared/helpers/mitt';
import Icon from 'next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { ONBOARDING_TOUR_EVENTS, buildStepCatalog } from './onboardingSteps';

const emit = defineEmits(['close']);

const { t } = useI18n();
const router = useRouter();
const { accountId } = useAccount();
const {
  flags,
  score,
  isFullyComplete,
  tourCompletedAt,
  lastStepIndex,
  dismissExplicit,
  markTourCompleted,
  refresh,
} = useOnboardingState();
const currentUser = useMapGetter('getCurrentUser');

const panelRef = ref(null);

const handleClickOutside = event => {
  if (panelRef.value && !panelRef.value.contains(event.target)) emit('close');
};
const handleEsc = event => {
  if (event.key === 'Escape') emit('close');
};

onMounted(() => {
  document.addEventListener('mousedown', handleClickOutside);
  document.addEventListener('keydown', handleEsc);
  refresh({ force: true });
});
onBeforeUnmount(() => {
  document.removeEventListener('mousedown', handleClickOutside);
  document.removeEventListener('keydown', handleEsc);
});

const steps = computed(() =>
  buildStepCatalog({ t, flags: flags.value }).map(step => ({
    ...step,
    onClick: () => {
      emit('close');
      router.push(step.route(accountId.value));
    },
  }))
);

const firstName = computed(() => {
  const raw = currentUser.value?.name || '';
  return raw.trim().split(/\s+/)[0] || '';
});

// Whimsical time-to-finish estimate. Worth ~1.5min per outstanding task —
// the value is honest enough that users don't feel sold to and it nudges
// them to keep going.
const remainingMinutes = computed(() => {
  const todo = Math.max(score.value.total - score.value.done, 0);
  return Math.max(Math.round(todo * 1.5), todo > 0 ? 1 : 0);
});

const tourLabel = computed(() => {
  if (tourCompletedAt.value && isFullyComplete.value) {
    return t('ONBOARDING_TOUR.PANEL.RETAKE_TOUR');
  }
  if (tourCompletedAt.value || lastStepIndex.value > 0) {
    return t('ONBOARDING_TOUR.PANEL.RESUME_TOUR');
  }
  return t('ONBOARDING_TOUR.PANEL.START_TOUR');
});

const startTour = () => {
  emit('close');
  emitter.emit(ONBOARDING_TOUR_EVENTS.START);
};

const finishOnboarding = async () => {
  await markTourCompleted();
  emit('close');
};

const dismissPanel = async () => {
  await dismissExplicit();
  emit('close');
};
</script>

<template>
  <div
    ref="panelRef"
    class="fixed bottom-20 ltr:right-4 rtl:left-4 z-50 w-[420px] max-w-[calc(100vw-2rem)] max-h-[calc(100vh-7rem)] flex flex-col rounded-3xl border border-n-teal-7/30 bg-n-surface-1 shadow-[0_24px_70px_-20px_rgba(0,0,0,0.55),0_0_0_1px_rgba(19,203,141,0.08)] overflow-hidden"
    role="dialog"
    :aria-label="t('ONBOARDING_TOUR.PANEL.TITLE')"
  >
    <header
      class="relative px-6 pt-6 pb-5 border-b border-n-weak/60 bg-gradient-to-br from-n-teal-9/20 via-n-teal-3/10 to-transparent"
    >
      <span
        aria-hidden="true"
        class="absolute -top-12 -right-12 size-40 rounded-full bg-n-teal-9/15 blur-3xl pointer-events-none"
      />
      <div class="flex items-start gap-3 relative">
        <span
          class="inline-flex items-center justify-center size-11 rounded-2xl bg-gradient-to-br from-n-teal-9 to-n-teal-10 text-white shrink-0 shadow-lg ring-1 ring-white/10"
        >
          <Icon icon="i-lucide-rocket" class="size-5" />
        </span>
        <div class="flex flex-col flex-1 min-w-0">
          <p
            class="text-[10.5px] font-bold uppercase tracking-[0.18em] text-n-teal-11 m-0"
          >
            {{ t('ONBOARDING_TOUR.PANEL.EYEBROW') }}
          </p>
          <h2
            class="text-lg font-semibold text-n-slate-12 m-0 mt-0.5 leading-tight tracking-tight"
          >
            <template v-if="firstName">
              {{
                t('ONBOARDING_TOUR.PANEL.GREETING_NAMED', { name: firstName })
              }}
            </template>
            <template v-else>
              {{ t('ONBOARDING_TOUR.PANEL.GREETING') }}
            </template>
          </h2>
          <p class="text-xs text-n-slate-11 mt-1 m-0 leading-relaxed">
            {{
              t('ONBOARDING_TOUR.PANEL.SUBTITLE', {
                done: score.done,
                total: score.total,
              })
            }}
          </p>
        </div>
        <button
          type="button"
          class="shrink-0 inline-flex items-center justify-center size-7 rounded-md text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2 transition-colors cursor-pointer"
          :aria-label="t('ONBOARDING_TOUR.PANEL.DISMISS')"
          @click="emit('close')"
        >
          <Icon icon="i-lucide-x" class="size-4" />
        </button>
      </div>
      <div class="mt-5 relative">
        <div class="flex items-center justify-between mb-2">
          <span class="text-[11px] font-semibold text-n-slate-12">
            {{ score.percent }}%
          </span>
          <span
            v-if="remainingMinutes > 0"
            class="inline-flex items-center gap-1 text-[10.5px] font-medium text-n-slate-11"
          >
            <Icon icon="i-lucide-timer" class="size-3" />
            {{
              t('ONBOARDING_TOUR.PANEL.TIME_LEFT', { mins: remainingMinutes })
            }}
          </span>
        </div>
        <div
          class="h-1.5 w-full rounded-full bg-n-slate-3 dark:bg-n-slate-5 overflow-hidden"
        >
          <div
            class="h-full rounded-full bg-gradient-to-r from-n-teal-9 via-n-teal-10 to-n-teal-9 motion-safe:transition-all motion-safe:duration-700 motion-safe:ease-[cubic-bezier(0.16,1,0.3,1)]"
            :style="{ width: `${score.percent}%` }"
          />
        </div>
      </div>
    </header>

    <p
      class="px-6 pt-4 text-[12px] text-n-slate-11 m-0 leading-relaxed border-b border-n-weak/40 pb-4"
    >
      {{ t('ONBOARDING_TOUR.PANEL.INTRO') }}
    </p>

    <ul class="flex flex-col gap-2 px-4 py-4 overflow-y-auto flex-1">
      <li
        v-for="step in steps"
        :key="step.key"
        :tabindex="step.done ? -1 : 0"
        class="group flex items-center gap-3 rounded-xl border bg-n-alpha-1/40 p-3 transition-all cursor-pointer hover:border-n-teal-7/60 hover:bg-n-teal-3/20 hover:translate-x-0.5 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-teal-7"
        :class="
          step.done
            ? 'border-n-weak/40 opacity-70 cursor-default hover:translate-x-0 hover:border-n-weak/40 hover:bg-n-alpha-1/40'
            : 'border-n-weak/60'
        "
        @click="!step.done && step.onClick()"
        @keydown.enter="!step.done && step.onClick()"
      >
        <span
          class="inline-flex items-center justify-center size-9 rounded-full shrink-0 transition-all"
          :class="
            step.done
              ? 'bg-gradient-to-br from-n-teal-9 to-n-teal-10 text-white shadow-md'
              : 'bg-n-slate-3 text-n-slate-11 group-hover:bg-gradient-to-br group-hover:from-n-teal-9 group-hover:to-n-teal-10 group-hover:text-white group-hover:shadow-md'
          "
        >
          <Icon
            :icon="step.done ? 'i-lucide-check' : step.icon"
            class="size-4"
          />
        </span>
        <div class="flex-1 min-w-0">
          <p
            class="text-[12.5px] font-semibold text-n-slate-12 m-0 truncate"
            :class="{ 'line-through opacity-50': step.done }"
          >
            {{ step.title }}
          </p>
          <p
            v-if="!step.done"
            class="text-[11px] text-n-slate-11 mt-0.5 m-0 line-clamp-2 leading-snug"
          >
            {{ step.description }}
          </p>
          <p v-else class="text-[11px] text-n-teal-11 mt-0.5 m-0 font-medium">
            {{ t('ONBOARDING_TOUR.PANEL.DONE_LABEL') }}
          </p>
        </div>
        <Icon
          v-if="!step.done"
          icon="i-lucide-arrow-right"
          class="size-4 text-n-slate-10 group-hover:text-n-teal-11 group-hover:translate-x-0.5 transition-all"
        />
      </li>
    </ul>

    <footer
      class="px-5 py-4 border-t border-n-weak bg-gradient-to-b from-transparent to-n-alpha-1/40"
    >
      <div
        v-if="isFullyComplete"
        class="flex flex-col gap-3 items-center text-center"
      >
        <span
          class="inline-flex items-center justify-center size-10 rounded-full bg-gradient-to-br from-n-teal-9 to-n-teal-10 text-white shadow-md"
        >
          <Icon icon="i-lucide-sparkles" class="size-5" />
        </span>
        <p class="text-sm font-semibold text-n-teal-12 m-0">
          {{ t('ONBOARDING_TOUR.PANEL.ALL_DONE_TITLE') }}
        </p>
        <p class="text-xs text-n-slate-11 m-0 leading-relaxed">
          {{ t('ONBOARDING_TOUR.PANEL.ALL_DONE_BODY') }}
        </p>
        <Button
          :label="t('ONBOARDING_TOUR.PANEL.FINISH')"
          teal
          solid
          sm
          class="self-stretch"
          @click="finishOnboarding"
        />
      </div>
      <div v-else class="flex items-center justify-between gap-3">
        <button
          type="button"
          class="text-xs text-n-slate-11 hover:text-n-slate-12 font-medium transition-colors cursor-pointer"
          @click="dismissPanel"
        >
          {{ t('ONBOARDING_TOUR.PANEL.DISMISS') }}
        </button>
        <Button
          :label="tourLabel"
          teal
          solid
          sm
          icon="i-lucide-play"
          @click="startTour"
        />
      </div>
    </footer>
  </div>
</template>
