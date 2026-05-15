<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  task: { type: Object, required: true },
  isDragging: { type: Boolean, default: false },
});

const emit = defineEmits(['click', 'dragstart', 'dragend']);

const { t } = useI18n();

const PRIORITY_STYLES = {
  urgent: {
    accent: 'bg-n-ruby-9',
    chip: 'bg-n-ruby-3 text-n-ruby-11 ring-1 ring-inset ring-n-ruby-6',
    label: 'KANBAN.PRIORITY.URGENT',
  },
  high: {
    accent: 'bg-n-amber-9',
    chip: 'bg-n-amber-3 text-n-amber-11 ring-1 ring-inset ring-n-amber-6',
    label: 'KANBAN.PRIORITY.HIGH',
  },
  medium: {
    accent: 'bg-n-blue-9',
    chip: 'bg-n-blue-3 text-n-blue-11 ring-1 ring-inset ring-n-blue-6',
    label: 'KANBAN.PRIORITY.MEDIUM',
  },
  low: {
    accent: 'bg-n-slate-8',
    chip: 'bg-n-alpha-2 text-n-slate-11 ring-1 ring-inset ring-n-weak',
    label: 'KANBAN.PRIORITY.LOW',
  },
  none: null,
};

const priorityMeta = computed(
  () => PRIORITY_STYLES[props.task.priority] || null
);

const dueLabel = computed(() => {
  if (!props.task.due_date) return null;
  const date = new Date(props.task.due_date * 1000);
  const now = new Date();
  const diffMs = date.getTime() - now.getTime();
  const diffDays = Math.round(diffMs / (1000 * 60 * 60 * 24));
  let text;
  let tone = 'neutral';
  if (diffDays === 0) {
    text = t('KANBAN.CARD.DUE_TODAY');
    tone = 'soon';
  } else if (diffDays === 1) {
    text = t('KANBAN.CARD.DUE_TOMORROW');
    tone = 'soon';
  } else if (diffDays === -1) {
    text = t('KANBAN.CARD.DUE_YESTERDAY');
    tone = 'overdue';
  } else if (diffDays > 1) {
    text = t('KANBAN.CARD.DUE_IN_DAYS', { n: diffDays });
    tone = diffDays <= 3 ? 'soon' : 'neutral';
  } else {
    text = t('KANBAN.CARD.DUE_OVERDUE_DAYS', { n: -diffDays });
    tone = 'overdue';
  }
  return { text, tone };
});

const dueClass = computed(() => {
  if (!dueLabel.value) return '';
  if (dueLabel.value.tone === 'overdue') return 'text-n-ruby-11 bg-n-ruby-3';
  if (dueLabel.value.tone === 'soon') return 'text-n-amber-11 bg-n-amber-3';
  return 'text-n-slate-11 bg-n-alpha-2';
});

const visibleAssignees = computed(() =>
  (props.task.assignees || []).slice(0, 3)
);
const extraAssignees = computed(() =>
  Math.max(0, (props.task.assignees || []).length - 3)
);
</script>

<template>
  <article
    :draggable="true"
    class="kanban-card group relative flex flex-col gap-2.5 p-3 pl-3.5 rounded-xl bg-n-solid-1 ring-1 ring-n-weak cursor-grab transition-[transform,box-shadow,ring,opacity] duration-150 ease-out hover:ring-n-slate-7 hover:shadow-[0_4px_12px_-2px_rgba(0,0,0,0.18)] hover:-translate-y-px"
    :class="{
      'opacity-30 cursor-grabbing scale-[0.98] rotate-[-0.5deg]': isDragging,
    }"
    @click="emit('click', task)"
    @dragstart="emit('dragstart', task, $event)"
    @dragend="emit('dragend', $event)"
  >
    <span
      v-if="priorityMeta"
      class="absolute left-0 top-2 bottom-2 w-0.5 rounded-r-full"
      :class="priorityMeta.accent"
    />

    <header class="flex items-center justify-between gap-2 min-h-[18px]">
      <span
        class="text-[10px] font-mono tabular-nums text-n-slate-10 tracking-wide"
      >
        #{{ task.display_id }}
      </span>
      <span
        v-if="priorityMeta"
        class="inline-flex items-center gap-1 px-1.5 py-px rounded text-[10px] font-medium uppercase tracking-wider"
        :class="priorityMeta.chip"
      >
        {{ t(priorityMeta.label) }}
      </span>
    </header>

    <p
      class="text-sm font-medium text-n-slate-12 line-clamp-3 leading-snug tracking-[-0.01em]"
    >
      {{ task.title }}
    </p>

    <div v-if="(task.labels || []).length" class="flex flex-wrap gap-1">
      <span
        v-for="label in task.labels.slice(0, 3)"
        :key="label.id"
        class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-md text-[10px] font-medium text-n-slate-12 bg-n-alpha-1 ring-1 ring-inset ring-n-weak"
      >
        <span
          class="size-1.5 rounded-full"
          :style="{ backgroundColor: label.color }"
        />
        {{ label.title }}
      </span>
      <span
        v-if="task.labels.length > 3"
        class="inline-flex items-center px-1.5 py-0.5 rounded-md text-[10px] font-medium text-n-slate-10 bg-n-alpha-1"
      >
        +{{ task.labels.length - 3 }}
      </span>
    </div>

    <footer class="flex items-center justify-between gap-2 mt-0.5">
      <div class="flex items-center gap-1.5 text-[11px] text-n-slate-11">
        <span
          v-if="dueLabel"
          class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-md font-medium"
          :class="dueClass"
        >
          <span class="i-lucide-clock-3 size-3" />
          {{ dueLabel.text }}
        </span>
        <span
          v-if="(task.conversations || []).length"
          class="inline-flex items-center gap-0.5 tabular-nums"
        >
          <span class="i-lucide-message-square size-3.5" />
          {{ task.conversations.length }}
        </span>
        <span
          v-if="(task.contacts || []).length"
          class="inline-flex items-center gap-0.5 tabular-nums"
        >
          <span class="i-lucide-user size-3.5" />
          {{ task.contacts.length }}
        </span>
      </div>
      <div
        v-if="visibleAssignees.length"
        class="flex items-center -space-x-1.5"
      >
        <Avatar
          v-for="user in visibleAssignees"
          :key="user.id"
          :src="user.avatar_url"
          :name="user.name"
          :size="20"
          rounded-full
          class="ring-2 ring-n-solid-1"
        />
        <span
          v-if="extraAssignees"
          class="inline-flex items-center justify-center size-5 rounded-full bg-n-alpha-2 text-[9px] font-semibold text-n-slate-11 ring-2 ring-n-solid-1"
        >
          +{{ extraAssignees }}
        </span>
      </div>
    </footer>
  </article>
</template>
