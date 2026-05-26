<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  format,
  formatDistanceToNowStrict,
  fromUnixTime,
  isPast,
  isToday,
} from 'date-fns';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  task: { type: Object, required: true },
  funnelName: { type: String, default: '' },
  stageColor: { type: String, default: '' },
  selected: { type: Boolean, default: false },
  selectionActive: { type: Boolean, default: false },
  editing: { type: Boolean, default: false },
});

const emit = defineEmits([
  'click',
  'select',
  'titleEdit',
  'titleSubmit',
  'titleCancel',
]);

const onClick = event => {
  // While a selection batch is open, plain clicks toggle membership instead
  // of opening the drawer. Shift / Cmd / Ctrl always treat the click as a
  // selection action.
  if (
    props.selectionActive ||
    event.shiftKey ||
    event.metaKey ||
    event.ctrlKey
  ) {
    emit('select', { taskId: props.task.id, additive: true });
    return;
  }
  emit('click', props.task);
};

const onCheckboxClick = event => {
  event.stopPropagation();
  emit('select', { taskId: props.task.id, additive: true });
};

const onTitleDblClick = event => {
  if (props.selectionActive) return;
  event.stopPropagation();
  emit('titleEdit', props.task);
};

// Inline title editing: the board flips `editing` on this card and we swap
// the heading for an autofocused input. Enter saves, Escape rolls back.
const draftTitle = ref('');
const titleInputRef = ref(null);

watch(
  () => props.editing,
  flag => {
    if (!flag) return;
    draftTitle.value = props.task.title || '';
    nextTick(() => {
      titleInputRef.value?.focus();
      titleInputRef.value?.select();
    });
  },
  { immediate: true }
);

const commitTitle = () => {
  const next = draftTitle.value.trim();
  if (!next || next === props.task.title) {
    emit('titleCancel');
    return;
  }
  emit('titleSubmit', { taskId: props.task.id, title: next });
};
const cancelTitle = () => {
  draftTitle.value = props.task.title || '';
  emit('titleCancel');
};
const { t } = useI18n();

// Priority meta — `cls` controls the icon + label tint; the flag icon
// renders filled to match ClickUp's visual weight.
const PRIORITY_META = {
  none: null,
  low: {
    key: 'low',
    label: 'KANBAN.PRIORITY.LOW',
    cls: 'text-n-slate-11',
    fillCls: 'text-n-slate-9',
  },
  medium: {
    key: 'medium',
    label: 'KANBAN.PRIORITY.MEDIUM',
    cls: 'text-n-blue-11',
    fillCls: 'text-n-blue-9',
  },
  high: {
    key: 'high',
    label: 'KANBAN.PRIORITY.HIGH',
    cls: 'text-n-amber-11',
    fillCls: 'text-n-amber-9',
  },
  urgent: {
    key: 'urgent',
    label: 'KANBAN.PRIORITY.URGENT',
    cls: 'text-n-ruby-11',
    fillCls: 'text-n-ruby-9',
  },
};

const priorityMeta = computed(() => PRIORITY_META[props.task.priority]);

const dueDate = computed(() =>
  props.task.due_date ? fromUnixTime(props.task.due_date) : null
);
const isCompleted = computed(() => Boolean(props.task.completed_at));
const isOverdue = computed(
  () =>
    dueDate.value &&
    !isCompleted.value &&
    isPast(dueDate.value) &&
    !isToday(dueDate.value)
);
const dueRelative = computed(() => {
  if (!dueDate.value) return '';
  if (isToday(dueDate.value)) return t('KANBAN.CARD.DUE_TODAY');
  if (isOverdue.value) {
    return formatDistanceToNowStrict(dueDate.value, {
      addSuffix: true,
      unit: 'day',
    });
  }
  return format(dueDate.value, 'MMM d');
});

const hasDescription = computed(() =>
  Boolean(props.task.description && props.task.description.trim())
);

const primaryContact = computed(() => (props.task.contacts || [])[0] || null);
const extraContacts = computed(() =>
  Math.max(0, (props.task.contacts || []).length - 1)
);

const visibleAssignees = computed(() =>
  (props.task.assignees || []).slice(0, 3)
);
const extraAssignees = computed(() =>
  Math.max(0, (props.task.assignees || []).length - 3)
);

const estimateLabel = computed(() => {
  const minutes = props.task.estimate_minutes;
  if (!minutes || minutes <= 0) return '';
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  const remainder = minutes % 60;
  return remainder ? `${hours}h${remainder}m` : `${hours}h`;
});

const subtasksProgress = computed(() => {
  const total = props.task.subtasks_count || 0;
  if (!total) return null;
  const done = props.task.subtasks_completed_count || 0;
  return { done, total, percent: Math.round((done / total) * 100) };
});

const conversationsCount = computed(
  () => (props.task.conversations || []).length
);

// Native-title fallback summarising linked conversations on hover. Sales
// reps see channel + last activity without opening the drawer.
const conversationsTooltip = computed(() => {
  const conversations = props.task.conversations || [];
  if (!conversations.length) return '';
  return conversations
    .slice(0, 5)
    .map(conv => {
      const channel = conv.inbox_name || `Inbox #${conv.inbox_id}`;
      const status = conv.status ? ` · ${conv.status}` : '';
      return `#${conv.display_id} — ${channel}${status}`;
    })
    .join('\n');
});

const labelsVisible = computed(() => (props.task.labels || []).slice(0, 4));
const labelsExtra = computed(() =>
  Math.max(0, (props.task.labels || []).length - 4)
);
</script>

<template>
  <article
    class="kanban-card group relative flex flex-col gap-2.5 p-3.5 rounded-xl bg-n-solid-1 ring-1 cursor-pointer overflow-hidden"
    :class="selected ? 'ring-2 !ring-n-teal-9 bg-n-teal-3/20' : 'ring-n-weak'"
    @click="onClick"
  >
    <!-- Selection checkbox: revealed on hover or when a selection batch is
         already open. Click never propagates to the card body. -->
    <button
      type="button"
      class="absolute top-2 right-2 z-10 size-5 rounded-md ring-1 ring-n-slate-7 bg-n-solid-1/95 inline-flex items-center justify-center transition-opacity duration-150 cursor-pointer"
      :class="
        selected || selectionActive
          ? 'opacity-100 ring-n-teal-9 bg-n-teal-9 text-white'
          : 'opacity-0 group-hover:opacity-100 hover:ring-n-teal-9'
      "
      :aria-pressed="selected"
      :aria-label="selected ? 'Deselect task' : 'Select task'"
      @click="onCheckboxClick"
    >
      <span v-if="selected" class="i-lucide-check size-3" aria-hidden="true" />
    </button>
    <!-- Stage color rail — left border accent inherits column color. -->
    <span
      v-if="stageColor"
      aria-hidden="true"
      class="absolute left-0 top-0 bottom-0 w-[3px] opacity-90 transition-opacity duration-200 group-hover:opacity-100"
      :style="{ background: stageColor }"
    />

    <!-- Title row -->
    <header class="flex items-start gap-2 pl-1.5">
      <span
        v-if="isCompleted"
        class="i-lucide-check-circle-2 size-4 text-n-teal-11 flex-shrink-0 mt-0.5"
        aria-hidden="true"
      />
      <input
        v-if="editing"
        ref="titleInputRef"
        v-model="draftTitle"
        type="text"
        class="flex-1 text-[13.5px] font-semibold text-n-slate-12 leading-snug bg-n-background border border-n-teal-9 rounded-md px-2 py-1 focus:outline-none pr-7"
        @click.stop
        @blur="commitTitle"
        @keydown.enter.prevent="commitTitle"
        @keydown.escape.prevent="cancelTitle"
      />
      <h3
        v-else
        class="flex-1 text-[13.5px] font-semibold text-n-slate-12 leading-snug m-0 tracking-tight pr-7"
        :class="{ 'line-through opacity-60': isCompleted }"
        @dblclick="onTitleDblClick"
      >
        {{ task.title }}
      </h3>
    </header>

    <!-- Funnel subtitle -->
    <p
      v-if="funnelName"
      class="text-[11px] text-n-slate-11 m-0 truncate pl-1.5"
    >
      {{ t('KANBAN.CARD.IN_FUNNEL') }}
      <span class="text-n-teal-11 font-medium">{{ funnelName }}</span>
    </p>

    <!-- Meta rows: each only renders when there's a value, ClickUp-style -->
    <div class="flex flex-col gap-1.5 pl-1.5">
      <!-- Description hint + conversation count -->
      <div
        v-if="hasDescription || conversationsCount"
        class="flex items-center gap-3 text-n-slate-10"
      >
        <span
          v-if="hasDescription"
          class="i-lucide-align-left size-3.5"
          :aria-label="t('KANBAN.CARD.HAS_DESCRIPTION')"
        />
        <span
          v-if="conversationsCount"
          v-tooltip.top="conversationsTooltip"
          class="inline-flex items-center gap-1 text-[11px] cursor-help"
        >
          <Icon icon="i-lucide-message-square" class="size-3" />
          {{ conversationsCount }}
        </span>
      </div>

      <!-- Assignees stack -->
      <div
        v-if="visibleAssignees.length"
        class="flex items-center -space-x-1.5"
      >
        <Avatar
          v-for="assignee in visibleAssignees"
          :key="assignee.id"
          :src="assignee.avatar_url"
          :name="assignee.name"
          :size="22"
          rounded-full
          class="ring-2 ring-n-solid-1 transition-transform duration-200 ease-out hover:translate-y-[-1px] hover:z-10"
        />
        <span
          v-if="extraAssignees"
          class="inline-flex items-center justify-center size-[22px] rounded-full bg-n-alpha-2 ring-2 ring-n-solid-1 text-[10px] font-semibold text-n-slate-11"
        >
          +{{ extraAssignees }}
        </span>
      </div>

      <!-- Due date -->
      <div
        v-if="dueDate"
        class="flex items-center gap-1.5"
        :class="isOverdue ? 'text-n-ruby-11' : 'text-n-slate-11'"
      >
        <Icon icon="i-lucide-calendar" class="size-3.5" />
        <span class="text-[11px] font-medium">{{ dueRelative }}</span>
      </div>

      <!-- Priority -->
      <div
        v-if="priorityMeta"
        class="flex items-center gap-1.5"
        :class="priorityMeta.cls"
      >
        <span
          class="i-lucide-flag size-3.5"
          :class="priorityMeta.fillCls"
          aria-hidden="true"
        />
        <span class="text-[11px] font-medium">
          {{ t(priorityMeta.label) }}
        </span>
      </div>

      <!-- Estimate -->
      <div
        v-if="estimateLabel"
        class="flex items-center gap-1.5 text-n-slate-11"
      >
        <Icon icon="i-lucide-hourglass" class="size-3.5" />
        <span class="text-[11px] font-medium tabular-nums">
          {{ estimateLabel }}
        </span>
      </div>

      <!-- Labels -->
      <div
        v-if="labelsVisible.length"
        class="flex items-center gap-1.5 text-n-slate-11"
      >
        <Icon icon="i-lucide-tag" class="size-3.5" />
        <div class="flex items-center gap-1">
          <span
            v-for="label in labelsVisible"
            :key="label.id"
            v-tooltip.top="label.title"
            class="size-2 rounded-full ring-1 ring-inset ring-n-weak"
            :style="{ backgroundColor: label.color }"
          />
          <span v-if="labelsExtra" class="text-[10px] text-n-slate-10">
            +{{ labelsExtra }}
          </span>
        </div>
      </div>

      <!-- Subtasks progress -->
      <div
        v-if="subtasksProgress"
        class="flex items-center gap-1.5 text-n-slate-11"
      >
        <Icon icon="i-lucide-list-checks" class="size-3.5" />
        <span class="text-[11px] tabular-nums">
          {{ subtasksProgress.done }}/{{ subtasksProgress.total }}
          {{ t('KANBAN.CARD.SUBTASKS') }}
        </span>
        <span
          class="ml-1 h-1 flex-1 rounded-full bg-n-alpha-2 overflow-hidden max-w-[80px]"
        >
          <span
            class="block h-full rounded-full bg-n-teal-9 transition-[width] duration-300 ease-out"
            :style="{ width: `${subtasksProgress.percent}%` }"
          />
        </span>
      </div>
    </div>

    <!-- Primary contact footer — kept as a separate visual block so the
         operator sees who's on the other side without opening the drawer. -->
    <footer
      v-if="primaryContact"
      class="flex items-center gap-2 pt-2 pl-1.5 mt-0.5 border-t border-n-weak/50"
    >
      <Avatar
        :src="primaryContact.thumbnail || primaryContact.avatar_url"
        :name="primaryContact.name"
        :size="22"
        rounded-full
        class="ring-1 ring-n-weak"
      />
      <span class="text-[11px] text-n-slate-12 font-medium truncate min-w-0">
        {{ primaryContact.name }}
      </span>
      <span
        v-if="extraContacts"
        class="ml-auto inline-flex items-center justify-center min-w-[20px] h-5 px-1.5 rounded-full bg-n-alpha-2 text-[10px] font-semibold text-n-slate-11"
      >
        +{{ extraContacts }}
      </span>
    </footer>
  </article>
</template>

<style scoped>
/* Pin every hover transition to a single token so the whole card feels
   like one motion instead of a stack of independent ones. */
.kanban-card {
  transition:
    transform 220ms cubic-bezier(0.165, 0.84, 0.44, 1),
    box-shadow 220ms cubic-bezier(0.165, 0.84, 0.44, 1),
    border-color 200ms cubic-bezier(0.215, 0.61, 0.355, 1),
    --tw-ring-color 200ms cubic-bezier(0.215, 0.61, 0.355, 1);
}
.kanban-card:hover {
  transform: translateY(-1px);
  box-shadow: 0 12px 28px -10px rgba(0, 0, 0, 0.45);
  --tw-ring-color: rgba(20, 184, 166, 0.55);
}
.kanban-card:active {
  transform: translateY(0);
  transition-duration: 120ms;
}

@media (prefers-reduced-motion: reduce) {
  .kanban-card,
  .kanban-card * {
    transition: none !important;
  }
}
</style>
