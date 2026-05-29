<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  // Backend serializes due_date as a unix epoch (seconds), see Task#push_event_data.
  dueDate: {
    type: [Number, String, null],
    default: null,
  },
  status: {
    type: String,
    default: 'open',
  },
});

const { t } = useI18n();

const dueDateMs = computed(() => {
  if (!props.dueDate) return null;
  // Support both numeric epochs (Vuex hydrated from push_event_data) and ISO
  // strings (forms / draft state before persistence).
  if (typeof props.dueDate === 'number') return props.dueDate * 1000;
  const parsed = Date.parse(props.dueDate);
  return Number.isNaN(parsed) ? null : parsed;
});

const isClosed = computed(() => ['done', 'cancelled'].includes(props.status));

const isOverdue = computed(() => {
  if (!dueDateMs.value || isClosed.value) return false;
  return dueDateMs.value < Date.now();
});

const dateFormatter = new Intl.DateTimeFormat(undefined, {
  day: '2-digit',
  month: 'short',
  hour: '2-digit',
  minute: '2-digit',
});

const formatted = computed(() => {
  if (!dueDateMs.value) return null;
  return dateFormatter.format(new Date(dueDateMs.value));
});
</script>

<template>
  <span v-if="formatted" class="inline-flex">
    <span
      class="inline-flex items-center gap-1 text-[11px] tabular-nums rounded-md px-2 h-5 ring-1 ring-inset"
      :class="[
        isOverdue
          ? 'bg-n-ruby-3 text-n-ruby-12 ring-n-ruby-6'
          : 'bg-n-alpha-1 text-n-slate-11 ring-n-weak',
      ]"
    >
      <span
        class="size-3 flex-shrink-0"
        :class="[isOverdue ? 'i-lucide-alarm-clock' : 'i-lucide-calendar']"
      />
      <span>{{ formatted }}</span>
      <span
        v-if="isOverdue"
        class="ml-1 hidden sm:inline-flex items-center font-semibold uppercase tracking-wide text-[9px]"
      >
        {{ t('TASKS.ROW.OVERDUE_BADGE') }}
      </span>
    </span>
  </span>
</template>
