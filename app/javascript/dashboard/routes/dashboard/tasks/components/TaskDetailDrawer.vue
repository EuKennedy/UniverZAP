<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import TasksAPI from 'dashboard/api/tasks';
import TaskUrgencyBadge from './TaskUrgencyBadge.vue';
import TaskDueDateChip from './TaskDueDateChip.vue';
import TaskCommentsList from './TaskCommentsList.vue';
import TaskActivityFeed from './TaskActivityFeed.vue';
import TaskRecurrenceForm from './TaskRecurrenceForm.vue';
import TaskConvertToKanbanModal from './TaskConvertToKanbanModal.vue';

const props = defineProps({
  task: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['close', 'updated', 'deleted', 'completed']);

const { t } = useI18n();
const store = useStore();

const TABS = [
  { key: 'description', labelKey: 'TASKS.DETAIL.TABS.DESCRIPTION' },
  { key: 'comments', labelKey: 'TASKS.DETAIL.TABS.COMMENTS' },
  { key: 'activity', labelKey: 'TASKS.DETAIL.TABS.ACTIVITY' },
];

const activeTab = ref('description');

const isClosed = computed(() =>
  ['done', 'cancelled'].includes(props.task?.status)
);

const statusBadgeText = computed(() => {
  if (isClosed.value) return t('TASKS.STATUS.DONE').slice(0, 2);
  return String(props.task?.display_id ?? '');
});

const titleDraft = ref(props.task?.title || '');
const descriptionDraft = ref(props.task?.description?.text || '');
const recurrenceDraft = ref(props.task?.recurrence_rule || {});

const comments = ref([]);
const activities = ref([]);
const isLoadingActivities = ref(false);
const isPostingComment = ref(false);
const isSavingTitle = ref(false);
const isSavingDescription = ref(false);
const isConvertOpen = ref(false);

// Pull the activity stream every time we open a new task. Comments live on the
// activity controller indirectly — for the MVP we keep them in the task payload
// (T1 surfaces `comments_count`; we lazy-load the full list as a follow-up).
const loadActivities = async () => {
  if (!props.task?.id) return;
  isLoadingActivities.value = true;
  try {
    const response = await TasksAPI.fetchActivities(props.task.id);
    activities.value = response.data?.data || response.data || [];
  } finally {
    isLoadingActivities.value = false;
  }
};

watch(
  () => props.task?.id,
  () => {
    titleDraft.value = props.task?.title || '';
    descriptionDraft.value = props.task?.description?.text || '';
    recurrenceDraft.value = props.task?.recurrence_rule || {};
    activeTab.value = 'description';
    if (props.task?.id) loadActivities();
  },
  { immediate: true }
);

const persistField = async patch => {
  if (!props.task?.id) return null;
  try {
    const updated = await store.dispatch('tasks/update', {
      id: props.task.id,
      ...patch,
    });
    emit('updated', updated);
    return updated;
  } catch (error) {
    useAlert(error?.message || t('TASKS.DETAIL.MUTATION_ERROR'));
    return null;
  }
};

const saveRecurrence = async rule => {
  recurrenceDraft.value = rule;
  await persistField({ recurrence_rule: rule || {} });
};

const openConvert = () => {
  isConvertOpen.value = true;
};

const handleConvert = async ({ funnelId, funnelStageId }) => {
  if (!props.task?.id) return;
  try {
    await store.dispatch('tasks/convertToKanbanCard', {
      id: props.task.id,
      funnelId,
      funnelStageId,
    });
    useAlert(t('TASKS.CONVERT.SUCCESS'));
    isConvertOpen.value = false;
  } catch (error) {
    useAlert(error?.message || t('TASKS.CONVERT.ERROR'));
  }
};

const saveTitle = async () => {
  if (titleDraft.value.trim() === (props.task?.title || '')) return;
  isSavingTitle.value = true;
  await persistField({ title: titleDraft.value.trim() });
  isSavingTitle.value = false;
};

const saveDescription = async () => {
  const existing = props.task?.description?.text || '';
  if (descriptionDraft.value === existing) return;
  isSavingDescription.value = true;
  await persistField({
    description: descriptionDraft.value
      ? { type: 'doc', text: descriptionDraft.value }
      : {},
  });
  isSavingDescription.value = false;
};

const complete = async () => {
  if (!props.task?.id) return;
  try {
    const updated = await store.dispatch('tasks/complete', props.task.id);
    useAlert(t('TASKS.DETAIL.COMPLETE_SUCCESS'));
    emit('completed', updated);
    loadActivities();
  } catch (error) {
    useAlert(error?.message || t('TASKS.DETAIL.MUTATION_ERROR'));
  }
};

const reopen = async () => {
  const updated = await persistField({ status: 'open', completed_at: null });
  if (updated) loadActivities();
};

const destroy = async () => {
  if (!props.task?.id) return;
  if (!window.confirm(t('TASKS.DETAIL.ACTIONS.DELETE_CONFIRM'))) return;
  try {
    await store.dispatch('tasks/delete', props.task.id);
    useAlert(t('TASKS.DETAIL.DELETE_SUCCESS'));
    emit('deleted', props.task.id);
  } catch (error) {
    useAlert(error?.message || t('TASKS.DETAIL.DELETE_ERROR'));
  }
};

const postComment = async ({ text }) => {
  if (!props.task?.id) return;
  isPostingComment.value = true;
  try {
    const newComment = await store.dispatch('tasks/addComment', {
      id: props.task.id,
      body: { text },
    });
    comments.value = [newComment, ...comments.value];
  } finally {
    isPostingComment.value = false;
  }
};

const dateFormatter = new Intl.DateTimeFormat(undefined, {
  day: '2-digit',
  month: 'short',
  year: 'numeric',
});

const formatDate = ts => {
  if (!ts) return '—';
  const ms = typeof ts === 'number' ? ts * 1000 : Date.parse(ts);
  if (Number.isNaN(ms)) return '—';
  return dateFormatter.format(new Date(ms));
};
</script>

<template>
  <div>
    <aside
      v-if="task"
      class="fixed top-0 right-0 z-40 h-full w-full sm:w-[480px] flex flex-col bg-n-background ring-1 ring-n-weak shadow-2xl"
      data-test-id="task-detail-drawer"
    >
      <header class="flex items-start gap-3 px-5 py-4 border-b border-n-weak">
        <span
          class="size-7 grid place-content-center rounded-md text-[10px] uppercase tracking-wide font-semibold flex-shrink-0"
          :class="[
            isClosed
              ? 'bg-n-teal-3 text-n-teal-12 ring-1 ring-inset ring-n-teal-6'
              : 'bg-n-blue-3 text-n-blue-12 ring-1 ring-inset ring-n-blue-6',
          ]"
        >
          {{ statusBadgeText }}
        </span>
        <input
          v-model="titleDraft"
          type="text"
          class="flex-1 bg-transparent outline-none text-[16px] font-semibold text-n-slate-12 tracking-tight border-0 focus:bg-n-alpha-1 rounded px-1 -mx-1"
          @blur="saveTitle"
          @keydown.enter.prevent="saveTitle"
        />
        <button
          type="button"
          class="size-7 grid place-content-center rounded-md text-n-slate-11 hover:bg-n-alpha-1 flex-shrink-0"
          :aria-label="t('TASKS.DETAIL.CLOSE')"
          @click="emit('close')"
        >
          <span class="i-lucide-x size-4" />
        </button>
      </header>

      <section
        class="flex flex-wrap items-center gap-2 px-5 py-3 border-b border-n-weak bg-n-alpha-1/40"
      >
        <TaskUrgencyBadge :urgency="task.urgency" size="sm" />
        <TaskDueDateChip :due-date="task.due_date" :status="task.status" />
        <div
          v-if="task.assignees && task.assignees.length"
          class="flex items-center -space-x-1.5"
        >
          <span
            v-for="assignee in task.assignees"
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
        </div>
      </section>

      <nav class="flex items-center gap-1 px-3 border-b border-n-weak">
        <button
          v-for="tab in TABS"
          :key="tab.key"
          type="button"
          class="text-[12px] h-9 px-3 rounded-t-md font-medium transition-colors border-b-2"
          :class="[
            activeTab === tab.key
              ? 'text-n-slate-12 border-n-brand'
              : 'text-n-slate-11 border-transparent hover:text-n-slate-12',
          ]"
          @click="activeTab = tab.key"
        >
          {{ t(tab.labelKey) }}
        </button>
      </nav>

      <div class="flex-1 overflow-y-auto px-5 py-5">
        <template v-if="activeTab === 'description'">
          <textarea
            v-model="descriptionDraft"
            rows="8"
            :placeholder="t('TASKS.DETAIL.DESCRIPTION_PLACEHOLDER')"
            class="w-full bg-n-alpha-1 ring-1 ring-inset ring-n-weak rounded-lg p-3 text-sm text-n-slate-12 placeholder:text-n-slate-10 outline-none resize-none"
            @blur="saveDescription"
          />

          <dl class="mt-5 grid grid-cols-2 gap-y-2 text-[12px]">
            <dt class="text-n-slate-10 uppercase tracking-wide">
              {{ t('TASKS.DETAIL.CREATED_AT') }}
            </dt>
            <dd class="text-n-slate-12 tabular-nums">
              {{ formatDate(task.created_at) }}
            </dd>
            <dt class="text-n-slate-10 uppercase tracking-wide">
              {{ t('TASKS.DETAIL.UPDATED_AT') }}
            </dt>
            <dd class="text-n-slate-12 tabular-nums">
              {{ formatDate(task.updated_at) }}
            </dd>
          </dl>

          <div class="mt-5">
            <TaskRecurrenceForm
              :model-value="recurrenceDraft"
              @update:model-value="saveRecurrence"
            />
          </div>
        </template>

        <template v-else-if="activeTab === 'comments'">
          <TaskCommentsList
            :comments="comments"
            :is-submitting="isPostingComment"
            @submit="postComment"
          />
        </template>

        <template v-else>
          <div
            v-if="isLoadingActivities"
            class="flex items-center justify-center py-6"
          >
            <span
              class="i-lucide-loader-circle size-5 animate-spin text-n-slate-10"
            />
          </div>
          <TaskActivityFeed v-else :activities="activities" />
        </template>
      </div>

      <footer
        class="flex items-center gap-2 px-5 py-4 border-t border-n-weak bg-n-alpha-1/40"
      >
        <Button
          v-if="!isClosed"
          icon="i-lucide-check"
          :label="t('TASKS.DETAIL.ACTIONS.MARK_DONE')"
          size="sm"
          solid
          teal
          @click="complete"
        />
        <Button
          v-else
          icon="i-lucide-rotate-ccw"
          :label="t('TASKS.DETAIL.ACTIONS.REOPEN')"
          size="sm"
          outline
          slate
          @click="reopen"
        />
        <Button
          v-tooltip="t('TASKS.DETAIL.ACTIONS.CONVERT_TO_KANBAN')"
          icon="i-lucide-columns-3"
          :aria-label="t('TASKS.DETAIL.ACTIONS.CONVERT_TO_KANBAN')"
          size="sm"
          ghost
          blue
          data-test-id="task-detail-convert-trigger"
          @click="openConvert"
        />
        <Button
          v-tooltip="t('TASKS.DETAIL.ACTIONS.DELETE')"
          icon="i-lucide-trash-2"
          :aria-label="t('TASKS.DETAIL.ACTIONS.DELETE')"
          size="sm"
          ghost
          ruby
          @click="destroy"
        />
      </footer>
    </aside>

    <TaskConvertToKanbanModal
      v-if="isConvertOpen"
      @close="isConvertOpen = false"
      @submit="handleConvert"
    />
  </div>
</template>
