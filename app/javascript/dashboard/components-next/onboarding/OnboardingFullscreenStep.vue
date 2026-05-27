<script setup>
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  title: { type: String, required: true },
  body: { type: String, required: true },
  primaryLabel: { type: String, default: '' },
  secondaryLabel: { type: String, default: '' },
  step: { type: Number, default: 1 },
  total: { type: Number, default: 1 },
  chapter: { type: String, default: '' },
  voiceEnabled: { type: Boolean, default: false },
});

const emit = defineEmits(['primary', 'secondary', 'toggleVoice']);
const { t } = useI18n();
</script>

<template>
  <Teleport to="body">
    <div
      class="fixed inset-0 z-[60] flex items-center justify-center p-6 bg-n-slate-12/85 backdrop-blur-md"
      role="dialog"
      aria-modal="true"
      :aria-label="props.title"
    >
      <div
        class="relative w-full max-w-xl rounded-3xl bg-gradient-to-br from-n-surface-2 to-n-surface-1 border border-n-teal-7/30 shadow-2xl overflow-hidden"
      >
        <div
          class="absolute inset-x-0 top-0 h-1 bg-gradient-to-r from-n-teal-9 via-n-teal-10 to-n-teal-9"
        />

        <!-- Voice toggle — top-right corner. Opt-in narration. Persisted in
             localStorage by OnboardingTour. -->
        <button
          type="button"
          class="absolute top-4 right-4 inline-flex items-center justify-center size-9 rounded-full transition-colors cursor-pointer"
          :class="
            voiceEnabled
              ? 'bg-n-teal-9/15 text-n-teal-11 hover:bg-n-teal-9/25'
              : 'bg-n-alpha-2 text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-3'
          "
          :aria-pressed="voiceEnabled"
          :aria-label="
            voiceEnabled
              ? t('ONBOARDING_TOUR.TOUR.VOICE_OFF')
              : t('ONBOARDING_TOUR.TOUR.VOICE_ON')
          "
          :title="
            voiceEnabled
              ? t('ONBOARDING_TOUR.TOUR.VOICE_OFF')
              : t('ONBOARDING_TOUR.TOUR.VOICE_ON')
          "
          @click="emit('toggleVoice')"
        >
          <Icon
            :icon="voiceEnabled ? 'i-lucide-volume-2' : 'i-lucide-volume-x'"
            class="size-4"
          />
        </button>

        <div class="px-10 pt-10 pb-8 flex flex-col items-center text-center">
          <span
            class="inline-flex items-center justify-center size-16 rounded-full bg-gradient-to-br from-n-teal-9 to-n-teal-10 text-white shadow-xl mb-6"
          >
            <Icon icon="i-lucide-sparkles" class="size-7" />
          </span>

          <p
            v-if="props.chapter"
            class="text-[11px] font-bold uppercase tracking-[0.18em] text-n-teal-11 mb-2"
          >
            {{ props.chapter }}
          </p>
          <p
            class="text-[11px] font-semibold uppercase tracking-[0.18em] text-n-slate-10 mb-3"
          >
            {{
              t('ONBOARDING_TOUR.TOUR.STEP_PROGRESS', {
                current: props.step,
                total: props.total,
              })
            }}
          </p>

          <h1
            class="text-3xl font-semibold text-n-slate-12 m-0 leading-tight tracking-tight"
          >
            {{ props.title }}
          </h1>

          <p
            class="mt-4 text-base text-n-slate-11 m-0 leading-relaxed max-w-md"
          >
            {{ props.body }}
          </p>

          <div
            class="mt-9 flex flex-col-reverse sm:flex-row items-center gap-3 w-full sm:w-auto"
          >
            <button
              v-if="props.secondaryLabel"
              type="button"
              class="text-sm font-medium text-n-slate-11 hover:text-n-slate-12 px-4 py-2 transition-colors cursor-pointer"
              @click="emit('secondary')"
            >
              {{ props.secondaryLabel }}
            </button>
            <Button
              :label="props.primaryLabel"
              teal
              solid
              lg
              icon="i-lucide-arrow-right"
              trailing-icon
              class="min-w-48"
              @click="emit('primary')"
            />
          </div>
        </div>

        <div
          class="px-10 py-4 border-t border-n-weak/60 bg-n-alpha-1/30 flex items-center justify-center gap-2"
        >
          <span
            v-for="dot in props.total"
            :key="dot"
            class="size-1.5 rounded-full transition-all duration-300"
            :class="
              dot === props.step
                ? 'bg-n-teal-9 w-6'
                : dot < props.step
                  ? 'bg-n-teal-9'
                  : 'bg-n-slate-5'
            "
          />
        </div>
      </div>
    </div>
  </Teleport>
</template>
