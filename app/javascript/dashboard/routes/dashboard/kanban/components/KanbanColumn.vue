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
  selectedTaskIds: { type: Set, default: () => new Set() },
  inlineEditingTaskId: { type: [Number, null], default: null },
});

const emit = defineEmits([
  'cardClick',
  'cardSelect',
  'cardTitleEdit',
  'cardTitleSubmit',
  'cardTitleCancel',
  'taskMoved',
  'addTask',
]);

const selectionActive = computed(() => props.selectedTaskIds.size > 0);

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

// WIP limit visualisation: when the stage has a soft cap, the column header
// shows the count as `N / limit` and tints ruby once the cap is breached.
const wipLimit = computed(() =>
  props.stage.wip_limit && props.stage.wip_limit > 0
    ? props.stage.wip_limit
    : null
);
const isOverWip = computed(
  () => wipLimit.value !== null && props.tasks.length > wipLimit.value
);
const isAtWip = computed(
  () => wipLimit.value !== null && props.tasks.length === wipLimit.value
);

// Header icon mirrors the stage status — gives the operator a quick visual
// anchor before they even read the stage name.
const STATUS_ICON = {
  won: 'i-lucide-trophy',
  lost: 'i-lucide-x-circle',
  active: 'i-lucide-circle-dot',
};
const statusIcon = computed(
  () => STATUS_ICON[props.stage.status_type] || 'i-lucide-circle'
);

// Translate the stage's hex into rgba(...) variants so the header pill /
// translucent backgrounds can ride a single source of truth without
// hardcoding palettes per stage.
const tintedColor = computed(() => {
  const hex = props.stage.color || '#64748b';
  const rgb = hex
    .replace('#', '')
    .match(/.{2}/g)
    ?.map(part => parseInt(part, 16));
  if (!rgb || rgb.length !== 3) return null;
  const [r, g, b] = rgb;
  return {
    solid: `rgb(${r}, ${g}, ${b})`,
    soft: `rgba(${r}, ${g}, ${b}, 0.16)`,
    softer: `rgba(${r}, ${g}, ${b}, 0.08)`,
    ring: `rgba(${r}, ${g}, ${b}, 0.4)`,
  };
});

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
      class="sticky top-0 z-10 flex items-center gap-2 px-3 pt-3.5 pb-3 rounded-t-2xl backdrop-blur-md"
      :style="{
        background: `linear-gradient(to bottom, ${tintedColor?.softer}, transparent)`,
      }"
    >
      <!-- ClickUp-style colored pill: icon + uppercase label, tinted from stage.color -->
      <span
        class="inline-flex items-center gap-1.5 pl-2 pr-2.5 py-1 rounded-md text-[10.5px] font-bold uppercase tracking-[0.12em] truncate ring-1 ring-inset"
        :style="{
          background: tintedColor?.soft,
          color: tintedColor?.solid,
          borderColor: tintedColor?.ring,
        }"
        :title="stage.name"
      >
        <span
          :class="statusIcon"
          class="size-3 flex-shrink-0"
          aria-hidden="true"
        />
        {{ stage.name }}
      </span>
      <span
        class="text-[12px] tabular-nums font-semibold ml-0.5"
        :class="
          isOverWip
            ? 'text-n-ruby-11'
            : isAtWip
              ? 'text-n-amber-11'
              : 'text-n-slate-11'
        "
      >
        {{ tasks.length }}
        <span v-if="wipLimit !== null" class="text-n-slate-10 font-normal">
          / {{ wipLimit }}
        </span>
      </span>
      <span
        v-if="isOverWip"
        class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[9px] uppercase tracking-wider font-bold bg-n-ruby-3 text-n-ruby-11 ring-1 ring-inset ring-n-ruby-6 animate-pulse"
        :title="t('KANBAN.COLUMN.WIP_OVER_TOOLTIP', { limit: wipLimit })"
      >
        <span class="i-lucide-alert-triangle size-2.5" />
        {{ t('KANBAN.COLUMN.WIP_OVER') }}
      </span>
      <span
        v-if="statusBadge"
        class="inline-flex items-center px-1.5 py-0.5 rounded text-[9px] uppercase tracking-wider font-bold"
        :class="statusBadge.cls"
      >
        {{ t(statusBadge.label) }}
      </span>
      <span class="flex-1" aria-hidden="true" />
      <button
        v-if="canMutate"
        type="button"
        class="inline-flex items-center justify-center size-6 rounded-md text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2 transition-colors duration-150 cursor-pointer"
        :aria-label="t('KANBAN.COLUMN.ADD_TASK')"
        @click="emit('addTask', stage)"
      >
        <span class="i-lucide-plus size-4" />
      </button>
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
        <KanbanCard
          :task="task"
          :stage-color="stage.color"
          :selected="selectedTaskIds.has(task.id)"
          :selection-active="selectionActive"
          :editing="inlineEditingTaskId === task.id"
          @click="emit('cardClick', task)"
          @select="payload => emit('cardSelect', payload)"
          @title-edit="payload => emit('cardTitleEdit', payload)"
          @title-submit="payload => emit('cardTitleSubmit', payload)"
          @title-cancel="emit('cardTitleCancel')"
        />
      </template>
      <template #footer>
        <div
          v-if="!tasks.length"
          class="group/empty flex flex-col items-center justify-center gap-2 py-8 px-4 rounded-xl border border-dashed border-n-weak/70 select-none transition-colors hover:border-n-teal-7/60 hover:bg-n-teal-3/5"
        >
          <span
            class="inline-flex items-center justify-center size-9 rounded-full bg-n-alpha-1 ring-1 ring-inset ring-n-weak"
            :style="{ color: stage.color }"
          >
            <span class="i-lucide-sparkles size-4" />
          </span>
          <p
            class="text-[11px] text-n-slate-10 text-center leading-tight max-w-[180px]"
          >
            {{ t('KANBAN.COLUMN.EMPTY') }}
          </p>
          <button
            v-if="canMutate"
            type="button"
            class="opacity-0 group-hover/empty:opacity-100 transition-opacity duration-150 text-[11px] font-semibold text-n-teal-11 hover:text-n-teal-12 cursor-pointer"
            @click="emit('addTask', stage)"
          >
            + {{ t('KANBAN.COLUMN.ADD_TASK') }}
          </button>
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
