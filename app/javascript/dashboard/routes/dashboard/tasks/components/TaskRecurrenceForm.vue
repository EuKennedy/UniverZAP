<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  modelValue: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const TYPES = [
  { value: 'daily', labelKey: 'TASKS.RECURRENCE.DAILY' },
  { value: 'weekly', labelKey: 'TASKS.RECURRENCE.WEEKLY' },
  { value: 'monthly', labelKey: 'TASKS.RECURRENCE.MONTHLY' },
  { value: 'cron', labelKey: 'TASKS.RECURRENCE.CUSTOM' },
];

const WEEKDAYS = [
  { value: 0, labelKey: 'TASKS.RECURRENCE.WEEKDAYS.SUN' },
  { value: 1, labelKey: 'TASKS.RECURRENCE.WEEKDAYS.MON' },
  { value: 2, labelKey: 'TASKS.RECURRENCE.WEEKDAYS.TUE' },
  { value: 3, labelKey: 'TASKS.RECURRENCE.WEEKDAYS.WED' },
  { value: 4, labelKey: 'TASKS.RECURRENCE.WEEKDAYS.THU' },
  { value: 5, labelKey: 'TASKS.RECURRENCE.WEEKDAYS.FRI' },
  { value: 6, labelKey: 'TASKS.RECURRENCE.WEEKDAYS.SAT' },
];

const enabled = ref(Boolean(props.modelValue && props.modelValue.type));
const type = ref(props.modelValue?.type || 'daily');
const weekdays = ref(props.modelValue?.weekdays || [1]);
const dayOfMonth = ref(props.modelValue?.day || 1);
const cron = ref(props.modelValue?.cron || '0 9 * * 1-5');

const emitChange = () => {
  if (!enabled.value) {
    emit('update:modelValue', {});
    return;
  }
  const payload = { type: type.value };
  if (type.value === 'weekly') payload.weekdays = weekdays.value;
  if (type.value === 'monthly') payload.day = Number(dayOfMonth.value) || 1;
  if (type.value === 'cron') payload.cron = cron.value.trim();
  emit('update:modelValue', payload);
};

watch([enabled, type, weekdays, dayOfMonth, cron], emitChange, {
  deep: true,
});

const toggleWeekday = value => {
  if (weekdays.value.includes(value)) {
    weekdays.value = weekdays.value.filter(v => v !== value);
  } else {
    weekdays.value = [...weekdays.value, value].sort((a, b) => a - b);
  }
};

const isWeekdayActive = value => weekdays.value.includes(value);

const previewLabelKey = computed(() => {
  switch (type.value) {
    case 'daily':
      return 'TASKS.RECURRENCE.PREVIEW.DAILY';
    case 'weekly':
      return 'TASKS.RECURRENCE.PREVIEW.WEEKLY';
    case 'monthly':
      return 'TASKS.RECURRENCE.PREVIEW.MONTHLY';
    default:
      return 'TASKS.RECURRENCE.PREVIEW.CUSTOM';
  }
});
</script>

<template>
  <section
    class="flex flex-col gap-3 px-4 py-3 rounded-xl bg-n-alpha-1 ring-1 ring-inset ring-n-weak"
    data-test-id="task-recurrence-form"
  >
    <label
      class="flex items-center justify-between gap-2 cursor-pointer"
      data-test-id="task-recurrence-toggle"
    >
      <span class="text-sm text-n-slate-12 font-medium">
        {{ t('TASKS.RECURRENCE.TOGGLE') }}
      </span>
      <input v-model="enabled" type="checkbox" class="size-4 accent-n-brand" />
    </label>

    <template v-if="enabled">
      <div
        class="grid grid-cols-2 gap-1.5"
        data-test-id="task-recurrence-type-group"
      >
        <button
          v-for="opt in TYPES"
          :key="opt.value"
          type="button"
          class="text-[12px] h-8 px-2.5 rounded-md ring-1 ring-inset transition-colors"
          :class="[
            type === opt.value
              ? 'bg-n-blue-3 text-n-blue-12 ring-n-blue-6'
              : 'bg-n-alpha-1 text-n-slate-11 ring-n-weak hover:text-n-slate-12',
          ]"
          :data-test-id="`task-recurrence-type-${opt.value}`"
          @click="type = opt.value"
        >
          {{ t(opt.labelKey) }}
        </button>
      </div>

      <div v-if="type === 'weekly'" class="flex flex-wrap gap-1">
        <button
          v-for="day in WEEKDAYS"
          :key="day.value"
          type="button"
          class="text-[11px] uppercase tracking-wide size-8 rounded-md ring-1 ring-inset transition-colors"
          :class="[
            isWeekdayActive(day.value)
              ? 'bg-n-blue-9 text-white ring-n-blue-9'
              : 'bg-n-alpha-1 text-n-slate-11 ring-n-weak hover:text-n-slate-12',
          ]"
          :data-test-id="`task-recurrence-weekday-${day.value}`"
          @click="toggleWeekday(day.value)"
        >
          {{ t(day.labelKey) }}
        </button>
      </div>

      <label v-if="type === 'monthly'" class="flex flex-col gap-1">
        <span class="text-[12px] text-n-slate-10 font-medium">
          {{ t('TASKS.RECURRENCE.MONTHLY_DAY_LABEL') }}
        </span>
        <input
          v-model.number="dayOfMonth"
          type="number"
          min="1"
          max="31"
          class="px-3 py-2 rounded-lg bg-n-alpha-1 ring-1 ring-inset ring-n-weak focus:ring-n-slate-7 outline-none text-sm text-n-slate-12"
          data-test-id="task-recurrence-day-input"
        />
      </label>

      <label v-if="type === 'cron'" class="flex flex-col gap-1">
        <span class="text-[12px] text-n-slate-10 font-medium">
          {{ t('TASKS.RECURRENCE.CRON_LABEL') }}
        </span>
        <input
          v-model="cron"
          type="text"
          :placeholder="t('TASKS.RECURRENCE.CRON_PLACEHOLDER')"
          class="px-3 py-2 rounded-lg bg-n-alpha-1 ring-1 ring-inset ring-n-weak focus:ring-n-slate-7 outline-none text-sm text-n-slate-12 font-mono"
          data-test-id="task-recurrence-cron-input"
        />
      </label>

      <p
        class="text-[11px] text-n-slate-10 leading-tight"
        data-test-id="task-recurrence-preview"
      >
        {{ t(previewLabelKey) }}
      </p>
    </template>
  </section>
</template>
