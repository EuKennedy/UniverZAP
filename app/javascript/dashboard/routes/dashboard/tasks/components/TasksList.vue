<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import TaskRow from './TaskRow.vue';
import TasksEmptyState from './TasksEmptyState.vue';

const props = defineProps({
  tasks: {
    type: Array,
    default: () => [],
  },
  groupBy: {
    type: String,
    default: 'urgency',
    validator: value =>
      ['none', 'urgency', 'status', 'due_date'].includes(value),
  },
  isFiltered: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['toggle', 'open', 'delete', 'create', 'reset']);

const { t } = useI18n();

const URGENCY_ORDER = ['urgent', 'high', 'medium', 'low', 'none'];
const STATUS_ORDER = ['open', 'in_progress', 'blocked', 'done', 'cancelled'];

const URGENCY_LABELS = {
  urgent: 'TASKS.URGENCY.URGENT',
  high: 'TASKS.URGENCY.HIGH',
  medium: 'TASKS.URGENCY.MEDIUM',
  low: 'TASKS.URGENCY.LOW',
  none: 'TASKS.URGENCY.NONE',
};

const STATUS_LABELS = {
  open: 'TASKS.STATUS.OPEN',
  in_progress: 'TASKS.STATUS.IN_PROGRESS',
  blocked: 'TASKS.STATUS.BLOCKED',
  done: 'TASKS.STATUS.DONE',
  cancelled: 'TASKS.STATUS.CANCELLED',
};

const collapsedGroups = ref(new Set());

const toggleGroup = key => {
  const next = new Set(collapsedGroups.value);
  if (next.has(key)) next.delete(key);
  else next.add(key);
  collapsedGroups.value = next;
};

const groupedTasks = computed(() => {
  if (props.groupBy === 'none') {
    return [{ key: 'all', label: null, tasks: props.tasks }];
  }

  if (props.groupBy === 'status') {
    const buckets = STATUS_ORDER.map(status => ({
      key: status,
      labelKey: STATUS_LABELS[status],
      tasks: [],
    }));
    const byKey = Object.fromEntries(buckets.map(b => [b.key, b]));
    props.tasks.forEach(task => {
      const bucket = byKey[task.status] || byKey.open;
      bucket.tasks.push(task);
    });
    return buckets.filter(bucket => bucket.tasks.length > 0);
  }

  // Default: urgency
  const buckets = URGENCY_ORDER.map(urgency => ({
    key: urgency,
    labelKey: URGENCY_LABELS[urgency],
    tasks: [],
  }));
  const byKey = Object.fromEntries(buckets.map(b => [b.key, b]));
  props.tasks.forEach(task => {
    const bucket = byKey[task.urgency] || byKey.none;
    bucket.tasks.push(task);
  });
  return buckets.filter(bucket => bucket.tasks.length > 0);
});
</script>

<template>
  <div class="flex flex-col flex-1 min-h-0">
    <TasksEmptyState
      v-if="!tasks.length"
      :variant="isFiltered ? 'filtered' : 'default'"
      data-test-id="tasks-list-empty"
      @create="emit('create')"
      @reset="emit('reset')"
    />
    <div v-else class="flex-1 overflow-y-auto px-3 py-3">
      <section
        v-for="group in groupedTasks"
        :key="group.key"
        class="mb-4"
        data-test-id="tasks-list-group"
      >
        <button
          v-if="group.labelKey"
          type="button"
          class="flex items-center gap-2 w-full text-left mb-1.5 px-2 py-1 rounded hover:bg-n-alpha-1"
          @click="toggleGroup(group.key)"
        >
          <span
            class="size-3 flex-shrink-0 transition-transform"
            :class="[
              collapsedGroups.has(group.key)
                ? 'i-lucide-chevron-right'
                : 'i-lucide-chevron-down',
            ]"
          />
          <span
            class="text-[11px] uppercase tracking-[0.1em] font-semibold text-n-slate-11"
          >
            {{ t(group.labelKey) }}
          </span>
          <span
            class="ml-1 text-[11px] tabular-nums px-1.5 h-4 rounded-md bg-n-alpha-1 text-n-slate-10 ring-1 ring-inset ring-n-weak"
          >
            {{ group.tasks.length }}
          </span>
        </button>
        <div
          v-if="!collapsedGroups.has(group.key)"
          class="rounded-xl bg-n-solid-1 ring-1 ring-n-weak overflow-hidden"
        >
          <TaskRow
            v-for="task in group.tasks"
            :key="task.id"
            :task="task"
            @toggle="emit('toggle', $event)"
            @open="emit('open', $event)"
            @delete="emit('delete', $event)"
          />
        </div>
      </section>
    </div>
  </div>
</template>
