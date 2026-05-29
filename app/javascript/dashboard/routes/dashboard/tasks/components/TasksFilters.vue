<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  filters: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['update', 'clear']);

const { t } = useI18n();

const STATUS_OPTIONS = [
  { value: null, labelKey: 'TASKS.FILTERS.ANY' },
  { value: 'open', labelKey: 'TASKS.STATUS.OPEN' },
  { value: 'in_progress', labelKey: 'TASKS.STATUS.IN_PROGRESS' },
  { value: 'blocked', labelKey: 'TASKS.STATUS.BLOCKED' },
  { value: 'done', labelKey: 'TASKS.STATUS.DONE' },
  { value: 'cancelled', labelKey: 'TASKS.STATUS.CANCELLED' },
];

const URGENCY_OPTIONS = [
  { value: null, labelKey: 'TASKS.FILTERS.ANY' },
  { value: 'urgent', labelKey: 'TASKS.URGENCY.URGENT' },
  { value: 'high', labelKey: 'TASKS.URGENCY.HIGH' },
  { value: 'medium', labelKey: 'TASKS.URGENCY.MEDIUM' },
  { value: 'low', labelKey: 'TASKS.URGENCY.LOW' },
  { value: 'none', labelKey: 'TASKS.URGENCY.NONE' },
];

const localQuery = ref(props.filters.q || '');

// Debounce search so each keystroke does not blow up the API.
let debounce = null;
watch(localQuery, value => {
  if (debounce) clearTimeout(debounce);
  debounce = setTimeout(() => {
    emit('update', { q: value || null });
  }, 250);
});

watch(
  () => props.filters.q,
  value => {
    if (value !== localQuery.value) localQuery.value = value || '';
  }
);

const setStatus = value => emit('update', { status: value });
const setUrgency = value => emit('update', { urgency: value });

const hasActiveFilters = computed(() => {
  return Boolean(
    props.filters.status ||
      props.filters.urgency ||
      props.filters.assignee_id ||
      props.filters.due_before ||
      props.filters.q
  );
});
</script>

<template>
  <div
    class="flex-shrink-0 flex items-center gap-2 px-6 h-12 border-b border-n-weak overflow-x-auto no-scrollbar"
  >
    <div
      class="flex items-center gap-2 min-w-[220px] max-w-xs px-2.5 py-1.5 rounded-lg bg-n-alpha-1 ring-1 ring-inset ring-n-weak focus-within:ring-n-slate-7 transition"
    >
      <span class="i-lucide-search size-3.5 text-n-slate-10 flex-shrink-0" />
      <input
        v-model="localQuery"
        type="text"
        :placeholder="t('TASKS.FILTERS.SEARCH_PLACEHOLDER')"
        class="flex-1 min-w-0 bg-transparent outline-none text-sm text-n-slate-12 placeholder:text-n-slate-10"
        data-test-id="tasks-filters-search"
      />
      <button
        v-if="localQuery"
        type="button"
        class="size-4 text-n-slate-10 hover:text-n-slate-12"
        @click="localQuery = ''"
      >
        <span class="i-lucide-x size-3.5" />
      </button>
    </div>

    <div
      class="inline-flex items-center gap-1 rounded-lg bg-n-alpha-1 ring-1 ring-inset ring-n-weak p-0.5"
    >
      <span class="px-2 text-[11px] uppercase tracking-wide text-n-slate-10">
        {{ t('TASKS.FILTERS.STATUS') }}
      </span>
      <button
        v-for="option in STATUS_OPTIONS"
        :key="`status-${option.value || 'any'}`"
        type="button"
        class="text-[12px] h-6 px-2 rounded-md transition-colors"
        :class="[
          (filters.status || null) === option.value
            ? 'bg-n-solid-1 text-n-slate-12 ring-1 ring-n-strong'
            : 'text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1',
        ]"
        @click="setStatus(option.value)"
      >
        {{ t(option.labelKey) }}
      </button>
    </div>

    <div
      class="inline-flex items-center gap-1 rounded-lg bg-n-alpha-1 ring-1 ring-inset ring-n-weak p-0.5"
    >
      <span class="px-2 text-[11px] uppercase tracking-wide text-n-slate-10">
        {{ t('TASKS.FILTERS.URGENCY') }}
      </span>
      <button
        v-for="option in URGENCY_OPTIONS"
        :key="`urgency-${option.value || 'any'}`"
        type="button"
        class="text-[12px] h-6 px-2 rounded-md transition-colors"
        :class="[
          (filters.urgency || null) === option.value
            ? 'bg-n-solid-1 text-n-slate-12 ring-1 ring-n-strong'
            : 'text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1',
        ]"
        @click="setUrgency(option.value)"
      >
        {{ t(option.labelKey) }}
      </button>
    </div>

    <button
      v-if="hasActiveFilters"
      type="button"
      class="ml-auto inline-flex items-center gap-1.5 text-[12px] text-n-slate-11 hover:text-n-slate-12 px-2 h-7 rounded-md hover:bg-n-alpha-1 flex-shrink-0"
      @click="emit('clear')"
    >
      <span class="i-lucide-filter-x size-3.5" />
      {{ t('TASKS.FILTERS.CLEAR') }}
    </button>
  </div>
</template>
