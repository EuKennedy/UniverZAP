<script setup>
import { computed } from 'vue';

const props = defineProps({
  label: { type: String, required: true },
  value: { type: [String, Number], required: true },
  hint: { type: String, default: '' },
  tone: {
    type: String,
    default: 'neutral',
    validator: value =>
      ['neutral', 'good', 'warning', 'danger'].includes(value),
  },
});

const valueClass = computed(
  () =>
    ({
      neutral: 'text-n-slate-12',
      good: 'text-n-teal-11',
      warning: 'text-n-amber-11',
      danger: 'text-n-ruby-11',
    })[props.tone]
);
</script>

<template>
  <div
    class="flex flex-col gap-1 rounded-xl border border-n-weak bg-n-solid-1 px-4 py-3 min-w-36 flex-1"
  >
    <span class="text-xs font-medium text-n-slate-11">{{ label }}</span>
    <span class="text-2xl font-semibold tabular-nums" :class="valueClass">
      {{ value }}
    </span>
    <span v-if="hint" class="text-xs text-n-slate-11">{{ hint }}</span>
  </div>
</template>
