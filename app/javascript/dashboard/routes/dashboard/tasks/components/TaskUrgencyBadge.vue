<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  urgency: {
    type: String,
    default: 'none',
  },
  size: {
    type: String,
    default: 'sm',
    validator: value => ['xs', 'sm'].includes(value),
  },
  showLabel: {
    type: Boolean,
    default: true,
  },
});

const { t } = useI18n();

// Palette mirrors the spec — solid for urgent/high (loud), tinted for the
// rest so a list with mixed urgencies stays scannable instead of garish.
const URGENCY_CLASSES = {
  urgent: 'bg-n-ruby-9 text-white ring-n-ruby-9/40',
  high: 'bg-n-amber-9 text-white ring-n-amber-9/40',
  medium: 'bg-n-amber-3 text-n-amber-12 ring-n-amber-6',
  low: 'bg-n-teal-3 text-n-teal-12 ring-n-teal-6',
  none: 'bg-n-slate-3 text-n-slate-12 ring-n-slate-6',
};

const URGENCY_DOT_CLASSES = {
  urgent: 'bg-n-ruby-9',
  high: 'bg-n-amber-9',
  medium: 'bg-n-amber-9',
  low: 'bg-n-teal-9',
  none: 'bg-n-slate-9',
};

const URGENCY_LABEL_KEYS = {
  urgent: 'TASKS.URGENCY.URGENT',
  high: 'TASKS.URGENCY.HIGH',
  medium: 'TASKS.URGENCY.MEDIUM',
  low: 'TASKS.URGENCY.LOW',
  none: 'TASKS.URGENCY.NONE',
};

const safeUrgency = computed(() =>
  Object.keys(URGENCY_CLASSES).includes(props.urgency) ? props.urgency : 'none'
);

const badgeClasses = computed(() => URGENCY_CLASSES[safeUrgency.value]);
const dotClasses = computed(() => URGENCY_DOT_CLASSES[safeUrgency.value]);
const label = computed(() => t(URGENCY_LABEL_KEYS[safeUrgency.value]));
const sizeClasses = computed(() =>
  props.size === 'xs'
    ? 'text-[10px] px-1.5 h-4 gap-1'
    : 'text-[11px] px-2 h-5 gap-1.5'
);
</script>

<template>
  <span
    class="inline-flex items-center rounded-md font-medium ring-1 ring-inset tracking-tight"
    :class="[badgeClasses, sizeClasses]"
  >
    <span class="rounded-full size-1.5 flex-shrink-0" :class="[dotClasses]" />
    <span v-if="showLabel">{{ label }}</span>
  </span>
</template>
