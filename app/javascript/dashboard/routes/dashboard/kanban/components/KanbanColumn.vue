<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import draggable from 'vuedraggable';

import Button from 'dashboard/components-next/button/Button.vue';
import KanbanCard from './KanbanCard.vue';

const props = defineProps({
  stage: { type: Object, required: true },
  tasks: { type: Array, required: true },
  canMutate: { type: Boolean, default: true },
});

const emit = defineEmits(['cardClick', 'taskMoved', 'addTask']);

const { t } = useI18n();

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

// vuedraggable mutates its bound array directly. We forward the raw event
// up to the board so it can dispatch the API move; the optimistic local
// reorder is already done by the time `onChange` fires. The board owns the
// rollback path if the API rejects the move.
const localTasks = computed({
  get() {
    return props.tasks;
  },
  set() {
    // no-op — board owns the source of truth
  },
});

const onChange = event => {
  const item = event.added?.element || event.moved?.element;
  if (!item) return;
  const newIndex =
    event.added?.newIndex ?? event.moved?.newIndex ?? props.tasks.length;
  emit('taskMoved', {
    taskId: item.id,
    stageId: props.stage.id,
    position: newIndex + 1,
  });
};
</script>

<template>
  <section
    class="kanban-column flex flex-col w-[300px] flex-shrink-0 rounded-2xl bg-n-alpha-1 ring-1 ring-inset ring-transparent transition-all duration-200 relative overflow-hidden"
  >
    <!-- Stage color accent top -->
    <span
      class="absolute inset-x-0 top-0 h-[3px] z-20"
      :style="{
        background: `linear-gradient(to right, ${stage.color}cc, ${stage.color}66)`,
      }"
    />

    <header
      class="sticky top-0 z-10 flex items-center gap-2 px-3.5 pt-4 pb-2.5 rounded-t-2xl backdrop-blur-md"
      :style="{
        background: `linear-gradient(to bottom, ${stage.color}10, transparent)`,
      }"
    >
      <span
        class="size-2.5 rounded-full flex-shrink-0 ring-2 ring-n-solid-1 shadow-[0_0_8px]"
        :style="{
          backgroundColor: stage.color,
          boxShadow: `0 0 8px ${stage.color}66`,
        }"
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
        class="inline-flex items-center justify-center min-w-[22px] h-5 px-1.5 rounded-md text-[11px] tabular-nums font-bold bg-n-solid-1 ring-1 ring-inset ring-n-weak"
        :style="{ color: stage.color }"
      >
        {{ tasks.length }}
      </span>
    </header>

    <draggable
      v-model="localTasks"
      :group="{ name: 'kanban-tasks', pull: canMutate, put: canMutate }"
      :animation="180"
      :delay="60"
      delay-on-touch-only
      :disabled="!canMutate"
      item-key="id"
      ghost-class="kanban-card-ghost"
      chosen-class="kanban-card-chosen"
      drag-class="kanban-card-drag"
      class="kanban-column-body flex-1 flex flex-col gap-2 px-2 pb-2 pt-1 min-h-[120px] overflow-y-auto overscroll-contain"
      @change="onChange"
    >
      <template #item="{ element: task }">
        <KanbanCard :task="task" @click="emit('cardClick', task)" />
      </template>
      <template #footer>
        <div
          v-if="!tasks.length"
          class="flex flex-col items-center justify-center gap-2 py-10 px-4 rounded-xl border border-dashed border-n-weak select-none"
        >
          <span class="i-lucide-inbox size-5 text-n-slate-10" />
          <p class="text-[11px] text-n-slate-10 text-center leading-tight">
            {{ t('KANBAN.COLUMN.EMPTY') }}
          </p>
        </div>
      </template>
    </draggable>

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

<style>
/* SortableJS exposes hooks via class names. Tune them here so dragging stays
   on-brand without coupling card markup to drag state. */
.kanban-card-ghost {
  opacity: 0.4;
  transform: scale(0.97) rotate(-0.6deg);
}
.kanban-card-ghost .kanban-card {
  background: rgba(20, 184, 166, 0.08);
  border-color: rgba(20, 184, 166, 0.5);
}
.kanban-card-chosen .kanban-card {
  box-shadow: 0 16px 48px -12px rgba(0, 0, 0, 0.5);
  cursor: grabbing;
}
.kanban-card-drag .kanban-card {
  transform: rotate(-1.2deg);
  box-shadow: 0 24px 56px -10px rgba(0, 0, 0, 0.7);
}
</style>
