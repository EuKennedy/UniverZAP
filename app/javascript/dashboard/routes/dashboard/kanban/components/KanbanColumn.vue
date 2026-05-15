<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import KanbanCard from './KanbanCard.vue';

const props = defineProps({
  stage: { type: Object, required: true },
  tasks: { type: Array, required: true },
  draggingTaskId: { type: [Number, null], default: null },
  canMutate: { type: Boolean, default: true },
});

const emit = defineEmits([
  'cardClick',
  'taskDragstart',
  'taskDragend',
  'taskDrop',
  'addTask',
]);

const { t } = useI18n();
const isOver = ref(false);

const STATUS_BADGE = {
  won: {
    cls: 'bg-n-teal-2 text-n-teal-11',
    label: 'KANBAN.STAGE.STATUS_WON',
  },
  lost: {
    cls: 'bg-n-ruby-2 text-n-ruby-11',
    label: 'KANBAN.STAGE.STATUS_LOST',
  },
  active: null,
};

const statusBadge = computed(() => STATUS_BADGE[props.stage.status_type]);

const onDragOver = event => {
  if (props.draggingTaskId == null) return;
  event.preventDefault();
  // eslint-disable-next-line no-param-reassign
  event.dataTransfer.dropEffect = 'move';
  isOver.value = true;
};

const onDragLeave = event => {
  if (event.currentTarget === event.target) isOver.value = false;
};

const computeDropPosition = event => {
  const list = event.currentTarget.querySelectorAll('[data-card-id]');
  let position = props.tasks.length + 1;
  for (let i = 0; i < list.length; i += 1) {
    const rect = list[i].getBoundingClientRect();
    const midpoint = rect.top + rect.height / 2;
    if (event.clientY < midpoint) {
      position = i + 1;
      break;
    }
  }
  return position;
};

const onDrop = event => {
  isOver.value = false;
  if (props.draggingTaskId == null) return;
  event.preventDefault();
  const position = computeDropPosition(event);
  emit('taskDrop', {
    stageId: props.stage.id,
    taskId: props.draggingTaskId,
    position,
  });
};
</script>

<template>
  <section
    class="flex flex-col w-[300px] flex-shrink-0 rounded-xl bg-n-alpha-1 border border-transparent transition-colors"
    :class="{ 'border-n-brand bg-n-brand/5': isOver }"
  >
    <header class="flex items-center gap-2 px-3 py-2.5">
      <span
        class="size-2 rounded-full flex-shrink-0"
        :style="{ backgroundColor: stage.color }"
      />
      <h2
        class="flex-1 text-sm font-medium text-n-slate-12 truncate"
        :title="stage.name"
      >
        {{ stage.name }}
      </h2>
      <span
        v-if="statusBadge"
        class="px-1.5 py-0.5 rounded text-[10px] uppercase tracking-wide font-medium"
        :class="statusBadge.cls"
      >
        {{ t(statusBadge.label) }}
      </span>
      <span
        class="text-xs tabular-nums text-n-slate-11 px-1.5 py-0.5 rounded bg-n-alpha-2"
      >
        {{ tasks.length }}
      </span>
    </header>

    <div
      class="flex-1 flex flex-col gap-2 px-2 py-1.5 min-h-[80px] overflow-y-auto"
      @dragover="onDragOver"
      @dragleave="onDragLeave"
      @drop="onDrop"
    >
      <KanbanCard
        v-for="task in tasks"
        :key="task.id"
        :task="task"
        :data-card-id="task.id"
        :is-dragging="task.id === draggingTaskId"
        @click="emit('cardClick', task)"
        @dragstart="(t2, e) => emit('taskDragstart', t2, e)"
        @dragend="e => emit('taskDragend', e)"
      />
      <p
        v-if="!tasks.length"
        class="text-xs text-n-slate-10 text-center py-6 select-none"
      >
        {{ t('KANBAN.COLUMN.EMPTY') }}
      </p>
    </div>

    <footer v-if="canMutate" class="px-2 pb-2 pt-1">
      <Button
        icon="i-lucide-plus"
        :label="t('KANBAN.COLUMN.ADD_TASK')"
        size="xs"
        ghost
        slate
        class="w-full justify-start"
        @click="emit('addTask', stage)"
      />
    </footer>
  </section>
</template>
