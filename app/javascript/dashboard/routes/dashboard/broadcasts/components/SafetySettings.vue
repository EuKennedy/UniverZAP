<script setup>
import { useI18n } from 'vue-i18n';

// Proteção anti-bloqueio do disparo. Os limites de cada campo são os mesmos
// que o backend impõe (Broadcast::HARD_LIMITS): o formulário só explica o que
// o servidor já garante.
const props = defineProps({
  modelValue: { type: Object, required: true },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const WEEKDAYS = [1, 2, 3, 4, 5, 6, 0];
const NUMBER_FIELDS = [
  { key: 'window_start', min: 0, max: 23 },
  { key: 'window_end', min: 1, max: 24 },
  { key: 'hourly_cap', min: 1, max: 60 },
  { key: 'daily_cap', min: 1, max: 300 },
  { key: 'delay_min', min: 20, max: 3600 },
  { key: 'delay_max', min: 20, max: 3600 },
  { key: 'quiet_hours', min: 0, max: 168 },
  { key: 'max_failures', min: 1, max: 20 },
];

const set = (key, value) =>
  emit('update:modelValue', { ...props.modelValue, [key]: value });

const weekdays = () => props.modelValue.weekdays || [1, 2, 3, 4, 5, 6];

const toggleDay = day => {
  const list = [...weekdays()];
  const index = list.indexOf(day);
  if (index === -1) list.push(day);
  else if (list.length > 1) list.splice(index, 1);
  set('weekdays', list);
};
</script>

<template>
  <div class="flex flex-col gap-4" data-testid="safety-settings">
    <p class="m-0 text-xs text-n-slate-11">
      {{ t('BROADCAST.SAFETY.HINT') }}
    </p>

    <div class="flex flex-col gap-1.5">
      <span class="text-xs font-medium text-n-slate-11">
        {{ t('BROADCAST.SAFETY.WEEKDAYS') }}
      </span>
      <div class="flex flex-wrap gap-1.5">
        <button
          v-for="day in WEEKDAYS"
          :key="day"
          type="button"
          class="size-8 rounded-full border text-xs transition-colors"
          :class="
            weekdays().includes(day)
              ? 'border-n-teal-8 bg-n-teal-3 text-n-teal-11'
              : 'border-n-weak text-n-slate-10'
          "
          :data-testid="`safety-day-${day}`"
          @click="toggleDay(day)"
        >
          {{ t(`BROADCAST.SAFETY.DAYS.D${day}`) }}
        </button>
      </div>
    </div>

    <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
      <label
        v-for="field in NUMBER_FIELDS"
        :key="field.key"
        class="flex flex-col gap-1.5"
      >
        <span class="text-xs font-medium text-n-slate-11">
          {{ t(`BROADCAST.SAFETY.${field.key.toUpperCase()}`) }}
        </span>
        <input
          :value="modelValue[field.key]"
          type="number"
          :min="field.min"
          :max="field.max"
          class="h-10 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8 !mb-0"
          :data-testid="`safety-${field.key}`"
          @input="set(field.key, Number($event.target.value))"
        />
      </label>
    </div>

    <label class="flex items-start gap-2 cursor-pointer">
      <input
        :checked="Boolean(modelValue.smart_timing)"
        type="checkbox"
        class="mt-0.5"
        data-testid="safety-smart-timing"
        @change="set('smart_timing', $event.target.checked)"
      />
      <span class="flex flex-col">
        <span class="text-sm text-n-slate-12">
          {{ t('BROADCAST.SAFETY.SMART_TIMING') }}
        </span>
        <span class="text-[11px] text-n-slate-10">
          {{ t('BROADCAST.SAFETY.SMART_TIMING_HINT') }}
        </span>
      </span>
    </label>
  </div>
</template>
