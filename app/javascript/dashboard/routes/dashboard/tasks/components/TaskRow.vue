<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import TaskUrgencyBadge from './TaskUrgencyBadge.vue';
import TaskDueDateChip from './TaskDueDateChip.vue';

const props = defineProps({
  task: {
    type: Object,
    required: true,
  },
  // T4 — bulk selection: a controlled checkbox lives in the row so the
  // parent can derive `selectedIds` without per-row local state drift.
  isSelected: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['toggle', 'open', 'delete', 'toggleSelected']);

const { t } = useI18n();

const isCompleted = computed(() =>
  ['done', 'cancelled'].includes(props.task.status)
);

const visibleAssignees = computed(() =>
  (props.task.assignees || []).slice(0, 3)
);
const remainingAssignees = computed(() =>
  Math.max(0, (props.task.assignees || []).length - 3)
);

const title = computed(() => props.task.title || t('TASKS.ROW.NO_TITLE'));
</script>

<template>
  <div
    class="group flex items-center gap-3 px-3 py-2 rounded-lg cursor-pointer border-b border-n-weak/60 last:border-b-0 hover:bg-n-alpha-1 transition-colors"
    :class="[isSelected && 'bg-n-blue-2/40']"
    data-test-id="task-row"
    @click="emit('open', task)"
  >
    <label
      class="size-4 grid place-content-center cursor-pointer flex-shrink-0"
      data-test-id="task-row-select"
      :aria-label="t('TASKS.BULK.SELECT_ROW')"
      @click.stop
    >
      <input
        type="checkbox"
        class="size-4 rounded-md accent-n-brand"
        :checked="isSelected"
        @change="emit('toggleSelected', task.id)"
      />
    </label>

    <button
      type="button"
      class="size-5 grid place-content-center rounded-md ring-1 ring-inset transition-colors flex-shrink-0"
      :class="[
        isCompleted
          ? 'bg-n-teal-9 ring-n-teal-9 text-white'
          : 'bg-transparent ring-n-strong hover:ring-n-slate-8',
      ]"
      :aria-label="t('TASKS.ROW.TOGGLE_STATUS')"
      data-test-id="task-row-toggle"
      @click.stop="emit('toggle', task)"
    >
      <span v-if="isCompleted" class="i-lucide-check size-3.5" />
    </button>

    <p
      class="flex-1 min-w-0 text-sm text-n-slate-12 truncate"
      :class="[isCompleted && 'line-through text-n-slate-10']"
      data-test-id="task-row-title"
    >
      {{ title }}
    </p>

    <div
      v-if="visibleAssignees.length"
      class="hidden md:flex items-center -space-x-1.5 flex-shrink-0"
    >
      <span
        v-for="assignee in visibleAssignees"
        :key="assignee.id"
        v-tooltip.top="assignee.name"
        class="ring-2 ring-n-background rounded-full"
      >
        <Avatar
          :name="assignee.name"
          :src="assignee.avatar_url"
          :size="22"
          rounded-full
        />
      </span>
      <span
        v-if="remainingAssignees > 0"
        class="size-[22px] grid place-content-center rounded-full bg-n-alpha-2 text-[10px] font-medium text-n-slate-11 ring-2 ring-n-background"
      >
        {{ `+${remainingAssignees}` }}
      </span>
    </div>

    <TaskUrgencyBadge
      v-if="task.urgency && task.urgency !== 'none'"
      :urgency="task.urgency"
      size="xs"
      :show-label="false"
      class="hidden sm:inline-flex flex-shrink-0"
    />

    <TaskDueDateChip
      :due-date="task.due_date"
      :status="task.status"
      class="hidden md:inline-flex flex-shrink-0"
    />

    <button
      type="button"
      class="size-7 grid place-content-center rounded-md text-n-slate-11 opacity-0 group-hover:opacity-100 hover:bg-n-alpha-2 transition-all flex-shrink-0"
      :aria-label="t('TASKS.ROW.MORE_ACTIONS')"
      @click.stop="emit('delete', task)"
    >
      <span class="i-lucide-trash-2 size-3.5" />
    </button>
  </div>
</template>
