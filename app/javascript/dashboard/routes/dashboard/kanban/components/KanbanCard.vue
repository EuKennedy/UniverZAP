<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  task: { type: Object, required: true },
});

const emit = defineEmits(['click']);

const { t } = useI18n();

const PRIORITY_STYLES = {
  urgent: {
    accent: 'bg-gradient-to-b from-n-ruby-9 to-n-ruby-11',
    chip: 'bg-n-ruby-3 text-n-ruby-11 ring-1 ring-inset ring-n-ruby-6',
    label: 'KANBAN.PRIORITY.URGENT',
  },
  high: {
    accent: 'bg-gradient-to-b from-n-amber-9 to-n-amber-11',
    chip: 'bg-n-amber-3 text-n-amber-11 ring-1 ring-inset ring-n-amber-6',
    label: 'KANBAN.PRIORITY.HIGH',
  },
  medium: {
    accent: 'bg-gradient-to-b from-n-blue-9 to-n-blue-11',
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

const primaryContact = computed(() => (props.task.contacts || [])[0] || null);
const extraContacts = computed(() =>
  Math.max(0, (props.task.contacts || []).length - 1)
);

const contactDetail = computed(() => {
  const c = primaryContact.value;
  if (!c) return null;
  return c.email || c.phone_number || null;
});

// Salesforce-style: "Added 2h ago" using task.created_at (unix seconds).
const addedAgoLabel = computed(() => {
  const ts = props.task.created_at;
  if (!ts) return null;
  const now = Math.floor(Date.now() / 1000);
  const diff = Math.max(0, now - Number(ts));
  if (diff < 60) return t('KANBAN.CARD.ADDED_NOW');
  const mins = Math.floor(diff / 60);
  if (mins < 60) return t('KANBAN.CARD.ADDED_MINUTES', { n: mins });
  const hours = Math.floor(mins / 60);
  if (hours < 24) return t('KANBAN.CARD.ADDED_HOURS', { n: hours });
  const days = Math.floor(hours / 24);
  if (days < 30) return t('KANBAN.CARD.ADDED_DAYS', { n: days });
  const months = Math.floor(days / 30);
  return t('KANBAN.CARD.ADDED_MONTHS', { n: months });
});

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
  if (dueLabel.value.tone === 'overdue')
    return 'text-n-ruby-11 bg-n-ruby-3 ring-1 ring-inset ring-n-ruby-6';
  if (dueLabel.value.tone === 'soon')
    return 'text-n-amber-11 bg-n-amber-3 ring-1 ring-inset ring-n-amber-6';
  return 'text-n-slate-11 bg-n-alpha-2 ring-1 ring-inset ring-n-weak';
});

const visibleAssignees = computed(() =>
  (props.task.assignees || []).slice(0, 3)
);
const extraAssignees = computed(() =>
  Math.max(0, (props.task.assignees || []).length - 3)
);

const hasTitle = computed(
  () =>
    props.task.title &&
    primaryContact.value &&
    !props.task.title.includes(primaryContact.value.name || '')
);
</script>

<template>
  <article
    class="kanban-card group relative flex flex-col gap-3 p-3.5 pl-4 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak cursor-grab transition-[transform,box-shadow,ring] duration-200 ease-out hover:ring-n-slate-7 hover:shadow-[0_8px_24px_-6px_rgba(0,0,0,0.32)] hover:-translate-y-0.5"
    @click="emit('click', task)"
  >
    <!-- Priority accent bar -->
    <span
      v-if="priorityMeta"
      class="absolute left-0 top-3 bottom-3 w-1 rounded-r-full"
      :class="priorityMeta.accent"
    />

    <!-- Top row: id + priority chip -->
    <header class="flex items-center justify-between gap-2 min-h-[16px]">
      <span
        class="text-[10px] font-mono tabular-nums text-n-slate-10 tracking-wide"
      >
        #{{ task.display_id }}
      </span>
      <span
        v-if="priorityMeta"
        class="inline-flex items-center gap-1 px-1.5 py-px rounded-md text-[9px] font-semibold uppercase tracking-[0.08em]"
        :class="priorityMeta.chip"
      >
        {{ t(priorityMeta.label) }}
      </span>
    </header>

    <!-- Contact hero -->
    <div v-if="primaryContact" class="flex items-center gap-3">
      <Avatar
        :src="primaryContact.thumbnail || primaryContact.avatar_url"
        :name="primaryContact.name"
        :size="40"
        rounded-full
        class="ring-2 ring-n-solid-1 shadow-[0_2px_8px_-2px_rgba(0,0,0,0.35)] flex-shrink-0"
      />
      <div class="flex flex-col min-w-0 flex-1 gap-0.5">
        <span
          class="text-[14px] font-semibold text-n-slate-12 truncate tracking-tight leading-tight"
        >
          {{ primaryContact.name }}
        </span>
        <span
          v-if="contactDetail"
          class="text-[11px] text-n-slate-11 truncate font-mono tabular-nums"
        >
          {{ contactDetail }}
        </span>
      </div>
      <span
        v-if="extraContacts"
        class="inline-flex items-center justify-center min-w-[22px] h-[22px] px-1.5 rounded-full bg-n-alpha-2 text-[10px] font-semibold text-n-slate-11 ring-1 ring-inset ring-n-weak"
      >
        +{{ extraContacts }}
      </span>
    </div>

    <!-- Custom title (only if differs from contact name) -->
    <p
      v-if="hasTitle || !primaryContact"
      class="text-[13px] text-n-slate-12 line-clamp-2 leading-snug"
      :class="{ 'font-semibold': !primaryContact }"
    >
      {{ task.title }}
    </p>

    <!-- Labels -->
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

    <!-- Footer: added-ago / due / conversations / assignees -->
    <footer
      class="flex items-center justify-between gap-2 pt-2 border-t border-n-weak/60"
    >
      <div
        class="flex items-center gap-1.5 text-[11px] text-n-slate-11 min-w-0 flex-1"
      >
        <!-- Added X ago -->
        <span
          v-if="addedAgoLabel"
          v-tooltip.top="addedAgoLabel"
          class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-md font-medium bg-n-alpha-1 ring-1 ring-inset ring-n-weak text-n-slate-11"
        >
          <span class="i-lucide-clock-3 size-3 text-n-slate-10" />
          {{ addedAgoLabel }}
        </span>
        <!-- Due date -->
        <span
          v-if="dueLabel"
          class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-md font-medium"
          :class="dueClass"
        >
          <span class="i-lucide-calendar-clock size-3" />
          {{ dueLabel.text }}
        </span>
        <!-- Conversations count -->
        <span
          v-if="(task.conversations || []).length"
          class="inline-flex items-center gap-1 tabular-nums text-n-slate-10"
        >
          <span class="i-lucide-message-square size-3.5" />
          {{ task.conversations.length }}
        </span>
      </div>
      <!-- Assignee stack -->
      <div
        v-if="visibleAssignees.length"
        class="flex items-center -space-x-1.5 flex-shrink-0"
      >
        <Avatar
          v-for="user in visibleAssignees"
          :key="user.id"
          :src="user.avatar_url"
          :name="user.name"
          :size="22"
          rounded-full
          class="ring-2 ring-n-solid-1"
        />
        <span
          v-if="extraAssignees"
          class="inline-flex items-center justify-center size-[22px] rounded-full bg-n-alpha-2 text-[9px] font-semibold text-n-slate-11 ring-2 ring-n-solid-1"
        >
          +{{ extraAssignees }}
        </span>
      </div>
    </footer>
  </article>
</template>
