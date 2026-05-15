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
const dropIndex = ref(null);

const STATUS_BADGE = {
  won: {
    cls: 'bg-n-teal-3 text-n-teal-11 ring-1 ring-inset ring-n-teal-6',
    label: 'KANBAN.STAGE.STATUS_WON',
  },
  lost: {
    cls: 'bg-n-ruby-3 text-n-ruby-11 ring-1 ring-inset ring-n-ruby-6',
    label: 'KANBAN.STAGE.STATUS_LOST',
  },
  active: null,
};

const statusBadge = computed(() => STATUS_BADGE[props.stage.status_type]);

const computeDropIndex = event => {
  const list = event.currentTarget.querySelectorAll('[data-card-id]');
  for (let i = 0; i < list.length; i += 1) {
    const rect = list[i].getBoundingClientRect();
    const midpoint = rect.top + rect.height / 2;
    if (event.clientY < midpoint) return i;
  }
  return list.length;
};

const onDragOver = event => {
  if (props.draggingTaskId == null) return;
  event.preventDefault();
  // eslint-disable-next-line no-param-reassign
  event.dataTransfer.dropEffect = 'move';
  isOver.value = true;
  dropIndex.value = computeDropIndex(event);
};

const onDragLeave = event => {
  if (event.currentTarget === event.target) {
    isOver.value = false;
    dropIndex.value = null;
  }
};

const onDrop = event => {
  if (props.draggingTaskId == null) return;
  event.preventDefault();
  const position = (dropIndex.value ?? props.tasks.length) + 1;
  isOver.value = false;
  dropIndex.value = null;
  emit('taskDrop', {
    stageId: props.stage.id,
    taskId: props.draggingTaskId,
    position,
  });
};
</script>

<template>
  <section
    class="kanban-column flex flex-col w-[300px] flex-shrink-0 rounded-2xl bg-n-alpha-1 ring-1 ring-inset ring-transparent transition-[box-shadow,background-color,ring-color] duration-200"
    :class="{
      'ring-n-brand bg-n-brand/[0.04] shadow-[0_0_0_1px_rgba(var(--brand-rgb,99,102,241),0.15)]':
        isOver,
    }"
  >
    <header
      class="sticky top-0 z-10 flex items-center gap-2 px-3 pt-3 pb-2 rounded-t-2xl bg-gradient-to-b from-n-alpha-1 to-transparent backdrop-blur-sm"
    >
      <span
        class="size-2 rounded-full flex-shrink-0 ring-2 ring-n-alpha-1"
        :style="{ backgroundColor: stage.color }"
      />
      <h2
        class="flex-1 text-[13px] font-semibold text-n-slate-12 truncate tracking-tight"
        :title="stage.name"
      >
        {{ stage.name }}
      </h2>
      <span
        v-if="statusBadge"
        class="px-1.5 py-0.5 rounded-md text-[9px] uppercase tracking-wider font-bold"
        :class="statusBadge.cls"
      >
        {{ t(statusBadge.label) }}
      </span>
      <span
        class="inline-flex items-center justify-center min-w-[20px] h-5 px-1.5 rounded-md text-[11px] tabular-nums font-semibold text-n-slate-11 bg-n-alpha-2"
      >
        {{ tasks.length }}
      </span>
    </header>

    <div
      class="kanban-column-body flex-1 flex flex-col gap-2 px-2 pb-2 pt-1 min-h-[120px] overflow-y-auto overscroll-contain"
      @dragover="onDragOver"
      @dragleave="onDragLeave"
      @drop="onDrop"
    >
      <template v-for="(task, idx) in tasks" :key="task.id">
        <div
          v-if="isOver && dropIndex === idx && task.id !== draggingTaskId"
          class="h-0.5 mx-1 rounded-full bg-n-brand shadow-[0_0_8px_var(--colors-n-brand)] animate-pulse"
        />
        <KanbanCard
          :task="task"
          :data-card-id="task.id"
          :is-dragging="task.id === draggingTaskId"
          @click="emit('cardClick', task)"
          @dragstart="(t2, e) => emit('taskDragstart', t2, e)"
          @dragend="e => emit('taskDragend', e)"
        />
      </template>
      <div
        v-if="isOver && dropIndex === tasks.length"
        class="h-0.5 mx-1 rounded-full bg-n-brand shadow-[0_0_8px_var(--colors-n-brand)] animate-pulse"
      />
      <div
        v-if="!tasks.length"
        class="flex flex-col items-center justify-center gap-2 py-10 px-4 rounded-xl border border-dashed border-n-weak select-none"
        :class="{ 'border-n-brand bg-n-brand/[0.06]': isOver }"
      >
        <span class="i-lucide-inbox size-5 text-n-slate-10" />
        <p class="text-[11px] text-n-slate-10 text-center leading-tight">
          {{ t('KANBAN.COLUMN.EMPTY') }}
        </p>
      </div>
    </div>

    <footer v-if="canMutate" class="px-2 pb-2 pt-1">
      <Button
        icon="i-lucide-plus"
        :label="t('KANBAN.COLUMN.ADD_TASK')"
        size="xs"
        ghost
        slate
        class="w-full justify-start hover:bg-n-alpha-2"
        @click="emit('addTask', stage)"
      />
    </footer>
  </section>
</template>
