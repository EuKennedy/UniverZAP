<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Thumbnail from 'dashboard/components/widgets/Thumbnail.vue';

const props = defineProps({
  task: { type: Object, required: true },
  isDragging: { type: Boolean, default: false },
});

const emit = defineEmits(['click', 'dragstart', 'dragend']);

const { t } = useI18n();

const PRIORITY_STYLES = {
  urgent: { dot: 'bg-n-ruby-9', label: 'KANBAN.PRIORITY.URGENT' },
  high: { dot: 'bg-n-amber-9', label: 'KANBAN.PRIORITY.HIGH' },
  medium: { dot: 'bg-n-blue-9', label: 'KANBAN.PRIORITY.MEDIUM' },
  low: { dot: 'bg-n-slate-8', label: 'KANBAN.PRIORITY.LOW' },
  none: null,
};

const priorityMeta = computed(() => PRIORITY_STYLES[props.task.priority] || null);

const dueLabel = computed(() => {
  if (!props.task.due_date) return null;
  const date = new Date(props.task.due_date * 1000);
  const now = new Date();
  const diffMs = date.getTime() - now.getTime();
  const diffDays = Math.round(diffMs / (1000 * 60 * 60 * 24));
  let text;
  if (diffDays === 0) text = t('KANBAN.CARD.DUE_TODAY');
  else if (diffDays === 1) text = t('KANBAN.CARD.DUE_TOMORROW');
  else if (diffDays === -1) text = t('KANBAN.CARD.DUE_YESTERDAY');
  else if (diffDays > 1) text = t('KANBAN.CARD.DUE_IN_DAYS', { n: diffDays });
  else text = t('KANBAN.CARD.DUE_OVERDUE_DAYS', { n: -diffDays });
  return { text, overdue: diffDays < 0 };
});

const visibleAssignees = computed(() => (props.task.assignees || []).slice(0, 3));
const extraAssignees = computed(() =>
  Math.max(0, (props.task.assignees || []).length - 3)
);
</script>

<template>
  <article
    :draggable="true"
    class="group flex flex-col gap-2 p-3 rounded-lg bg-n-solid-1 border border-n-weak cursor-grab transition-all hover:border-n-slate-7 hover:shadow-md"
    :class="{ 'opacity-40 cursor-grabbing': isDragging }"
    @click="emit('click', task)"
    @dragstart="emit('dragstart', task, $event)"
    @dragend="emit('dragend', $event)"
  >
    <header class="flex items-start justify-between gap-2">
      <span class="text-xs font-mono text-n-slate-10">#{{ task.display_id }}</span>
      <span
        v-if="priorityMeta"
        class="flex items-center gap-1 text-xs text-n-slate-11"
      >
        <span class="size-1.5 rounded-full" :class="priorityMeta.dot" />
        <span>{{ t(priorityMeta.label) }}</span>
      </span>
    </header>

    <p class="text-sm font-medium text-n-slate-12 line-clamp-3 leading-snug">
      {{ task.title }}
    </p>

    <div
      v-if="(task.labels || []).length"
      class="flex flex-wrap gap-1"
    >
      <span
        v-for="label in task.labels.slice(0, 3)"
        :key="label.id"
        class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs text-n-slate-12 bg-n-alpha-1"
      >
        <span
          class="size-1.5 rounded-full"
          :style="{ backgroundColor: label.color }"
        />
        {{ label.title }}
      </span>
    </div>

    <footer class="flex items-center justify-between gap-2 mt-1">
      <div class="flex items-center gap-2 text-xs text-n-slate-11">
        <span
          v-if="(task.conversations || []).length"
          class="inline-flex items-center gap-1"
        >
          <span class="i-lucide-message-circle size-3.5" />
          {{ task.conversations.length }}
        </span>
        <span
          v-if="(task.contacts || []).length"
          class="inline-flex items-center gap-1"
        >
          <span class="i-lucide-user size-3.5" />
          {{ task.contacts.length }}
        </span>
        <span
          v-if="dueLabel"
          class="inline-flex items-center gap-1"
          :class="{ 'text-n-ruby-10': dueLabel.overdue }"
        >
          <span class="i-lucide-calendar-clock size-3.5" />
          {{ dueLabel.text }}
        </span>
      </div>
      <div
        v-if="visibleAssignees.length"
        class="flex items-center -space-x-1.5"
      >
        <Thumbnail
          v-for="user in visibleAssignees"
          :key="user.id"
          :src="user.avatar_url"
          :username="user.name"
          size="20px"
          class="border-2 border-n-solid-1 rounded-full"
        />
        <span
          v-if="extraAssignees"
          class="inline-flex items-center justify-center size-5 rounded-full bg-n-alpha-2 text-[10px] font-medium text-n-slate-11 border-2 border-n-solid-1"
        >
          +{{ extraAssignees }}
        </span>
      </div>
    </footer>
  </article>
</template>
