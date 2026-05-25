<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
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
  isComplete,
  tourCompletedAt,
  dismissExplicit,
  markTourCompleted,
  refresh,
} = useOnboardingState();

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
      const path = step.route(accountId.value);
      emit('close');
      router.push(path);
    },
  }))
);

const tourLabel = computed(() => {
  if (!tourCompletedAt.value) return t('ONBOARDING_TOUR.PANEL.START_TOUR');
  if (!isComplete.value) return t('ONBOARDING_TOUR.PANEL.RESUME_TOUR');
  return t('ONBOARDING_TOUR.PANEL.RETAKE_TOUR');
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
    class="fixed bottom-20 ltr:right-4 rtl:left-4 z-50 w-[400px] max-w-[calc(100vw-2rem)] max-h-[calc(100vh-7rem)] flex flex-col rounded-2xl border border-n-weak bg-n-surface-2 shadow-2xl overflow-hidden"
    role="dialog"
    :aria-label="t('ONBOARDING_TOUR.PANEL.TITLE')"
  >
    <header
      class="flex items-start gap-3 px-5 pt-5 pb-4 border-b border-n-weak bg-gradient-to-br from-n-teal-3/40 to-transparent"
    >
      <span
        class="inline-flex items-center justify-center size-10 rounded-full bg-gradient-to-br from-n-teal-9 to-n-teal-10 text-white shrink-0 shadow-md"
      >
        <Icon icon="i-lucide-rocket" class="size-5" />
      </span>
      <div class="flex flex-col flex-1 min-w-0">
        <h2 class="text-sm font-semibold text-n-slate-12 m-0">
          {{ t('ONBOARDING_TOUR.PANEL.TITLE') }}
        </h2>
        <p class="text-xs text-n-slate-11 mt-0.5 m-0">
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
    </header>

    <div class="px-5 pt-4">
      <div class="h-1.5 w-full rounded-full bg-n-slate-3 overflow-hidden">
        <div
          class="h-full bg-gradient-to-r from-n-teal-9 to-n-teal-10 transition-all duration-500 ease-out"
          :style="{ width: `${score.percent}%` }"
        />
      </div>
      <p class="text-xs text-n-slate-11 mt-3 leading-relaxed">
        {{ t('ONBOARDING_TOUR.PANEL.INTRO') }}
      </p>
    </div>

    <ul class="flex flex-col gap-2 px-5 py-4 overflow-y-auto flex-1">
      <li
        v-for="step in steps"
        :key="step.key"
        class="group flex items-center gap-3 rounded-xl border border-n-weak/60 bg-n-alpha-1/50 p-3 transition-colors hover:border-n-teal-7/50"
      >
        <span
          class="inline-flex items-center justify-center size-8 rounded-full shrink-0 transition-colors"
          :class="
            step.done
              ? 'bg-n-teal-9 text-white'
              : 'bg-n-slate-3 text-n-slate-11 group-hover:bg-n-teal-3 group-hover:text-n-teal-11'
          "
        >
          <Icon
            :icon="step.done ? 'i-lucide-check' : step.icon"
            class="size-4"
          />
        </span>
        <div class="flex-1 min-w-0">
          <p
            class="text-xs font-semibold text-n-slate-12 m-0 truncate"
            :class="{ 'line-through opacity-50': step.done }"
          >
            {{ step.title }}
          </p>
          <p
            v-if="!step.done"
            class="text-[11px] text-n-slate-11 mt-0.5 m-0 line-clamp-2"
          >
            {{ step.description }}
          </p>
        </div>
        <Button
          v-if="!step.done"
          :label="step.cta"
          teal
          xs
          @click="step.onClick"
        />
      </li>
    </ul>

    <footer class="px-5 py-4 border-t border-n-weak bg-n-alpha-1/30">
      <div
        v-if="isComplete"
        class="flex flex-col gap-3 items-center text-center"
      >
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
