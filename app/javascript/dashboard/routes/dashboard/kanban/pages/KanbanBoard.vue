<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';
import KanbanColumn from '../components/KanbanColumn.vue';
import TaskFormModal from '../components/TaskFormModal.vue';
import KanbanTaskDrawer from '../components/KanbanTaskDrawer.vue';
import KanbanBulkActionBar from '../components/KanbanBulkActionBar.vue';
import KanbanSavedViews from '../components/KanbanSavedViews.vue';

const props = defineProps({
  funnelId: { type: [String, Number], required: true },
  taskId: { type: [String, Number], default: null },
});

const { t } = useI18n();
const router = useRouter();
const store = useStore();
const { accountScopedRoute } = useAccount();

const funnel = computed(() =>
  store.getters['funnels/getFunnel'](Number(props.funnelId))
);
const funnelUiFlags = useMapGetter('funnels/getUIFlags');
const taskUiFlags = useMapGetter('kanbanTasks/getUIFlags');
const currentUser = useMapGetter('getCurrentUser');

const isAdmin = computed(() => currentUser.value?.role === 'administrator');
const canMutate = computed(() => Boolean(funnel.value));

const stages = computed(() =>
  (funnel.value?.stages || []).slice().sort((a, b) => a.position - b.position)
);

const tasksByStage = stageId =>
  store.getters['kanbanTasks/getTasksByStage'](
    Number(props.funnelId),
    Number(stageId)
  );

const showTaskModal = ref(false);
const editingTask = ref(null);
const defaultStageId = ref(null);
const showDeleteConfirm = ref(false);
const taskPendingDelete = ref(null);
const search = ref('');
const priorityFilter = ref('all');
const assigneeFilter = ref(null); // null | user id
const labelFilter = ref(null); // null | label title
const dueFilter = ref('all'); // 'all' | 'overdue' | 'today' | 'week' | 'none'
const hasConversationFilter = ref(false);

// Swimlanes — when set, the board renders one horizontal lane per group key
// (assignee / priority / label). 'none' falls back to the classic single-row
// layout. Lane membership is computed live from the same filtered task list.
const GROUP_BY_OPTIONS = ['none', 'assignee', 'priority', 'label'];
const groupBy = ref('none');

// Bulk select state. We model it as a Set so adds/removes are O(1) and the
// child columns can do `Set.has(taskId)` for the selection ring.
const selectedTaskIds = ref(new Set());
const inlineEditingTaskId = ref(null);
const showBulkDeleteConfirm = ref(false);

const agentsList = useMapGetter('agents/getAgents');
const labelsList = useMapGetter('labels/getLabels');
const searchInputRef = ref(null);

const isDueWithinWeek = ts => {
  if (!ts) return false;
  const ms = Number(ts) * 1000;
  const now = Date.now();
  return ms >= now && ms - now < 7 * 24 * 60 * 60 * 1000;
};
const isOverdueTs = ts => {
  if (!ts) return false;
  return Number(ts) * 1000 < Date.now();
};
const isTodayTs = ts => {
  if (!ts) return false;
  const d = new Date(Number(ts) * 1000);
  const today = new Date();
  return (
    d.getFullYear() === today.getFullYear() &&
    d.getMonth() === today.getMonth() &&
    d.getDate() === today.getDate()
  );
};

const matchesFilters = task => {
  if (
    priorityFilter.value !== 'all' &&
    task.priority !== priorityFilter.value
  ) {
    return false;
  }
  if (
    assigneeFilter.value !== null &&
    !(task.assignees || []).some(a => a.id === assigneeFilter.value)
  ) {
    return false;
  }
  if (
    labelFilter.value !== null &&
    !(task.labels || []).some(l => l.title === labelFilter.value)
  ) {
    return false;
  }
  if (hasConversationFilter.value && !(task.conversations || []).length) {
    return false;
  }
  if (dueFilter.value !== 'all') {
    if (dueFilter.value === 'none' && task.due_date) return false;
    if (dueFilter.value === 'overdue' && !isOverdueTs(task.due_date))
      return false;
    if (dueFilter.value === 'today' && !isTodayTs(task.due_date)) return false;
    if (dueFilter.value === 'week' && !isDueWithinWeek(task.due_date))
      return false;
  }
  return true;
};

const matchesSearch = task => {
  const q = search.value.trim().toLowerCase();
  if (!q) return true;
  const title = (task.title || '').toLowerCase();
  const contactName = (task.contacts?.[0]?.name || '').toLowerCase();
  return title.includes(q) || contactName.includes(q);
};

const tasksByStageFiltered = stageId => {
  const all = tasksByStage(stageId) || [];
  return all.filter(task => matchesFilters(task) && matchesSearch(task));
};

// Lane membership helpers — a task can map to 0..N lanes depending on the
// group key. Labels are multi-valued; assignees default to "Unassigned" when
// empty so nothing falls off the board.
const UNASSIGNED_KEY = '__unassigned__';

const taskLaneKeys = task => {
  if (groupBy.value === 'assignee') {
    const ids = (task.assignees || []).map(a => a.id);
    return ids.length ? ids.map(id => `agent:${id}`) : [UNASSIGNED_KEY];
  }
  if (groupBy.value === 'priority') {
    return [`priority:${task.priority || 'none'}`];
  }
  if (groupBy.value === 'label') {
    const titles = (task.labels || []).map(l => l.title);
    return titles.length
      ? titles.map(title => `label:${title}`)
      : [UNASSIGNED_KEY];
  }
  return [];
};

const tasksByStageInLane = (stageId, laneKey) => {
  const all = tasksByStage(stageId) || [];
  return all.filter(task => {
    if (!matchesFilters(task) || !matchesSearch(task)) return false;
    return taskLaneKeys(task).includes(laneKey);
  });
};

function laneLabel(key, sampleTask) {
  if (key === UNASSIGNED_KEY) return t('KANBAN.BOARD.SWIMLANES.UNASSIGNED');
  if (key.startsWith('agent:')) {
    const id = Number(key.slice('agent:'.length));
    const found = (sampleTask.assignees || []).find(a => a.id === id);
    return found?.name || `#${id}`;
  }
  if (key.startsWith('priority:')) {
    const value = key.slice('priority:'.length);
    return t(`KANBAN.PRIORITY.${value.toUpperCase()}`);
  }
  if (key.startsWith('label:')) return key.slice('label:'.length);
  return key;
}

const lanes = computed(() => {
  if (groupBy.value === 'none') return [];
  const allTasks = stages.value
    .flatMap(s => tasksByStage(s.id) || [])
    .filter(task => matchesFilters(task) && matchesSearch(task));
  const seen = new Map();
  allTasks.forEach(task => {
    taskLaneKeys(task).forEach(key => {
      if (!seen.has(key)) {
        seen.set(key, { key, label: laneLabel(key, task), count: 0 });
      }
      seen.get(key).count += 1;
    });
  });
  return Array.from(seen.values()).sort((a, b) =>
    a.label.localeCompare(b.label)
  );
});

const clearAllFilters = () => {
  search.value = '';
  priorityFilter.value = 'all';
  assigneeFilter.value = null;
  labelFilter.value = null;
  dueFilter.value = 'all';
  hasConversationFilter.value = false;
};

const activeFilterCount = computed(() => {
  let n = 0;
  if (priorityFilter.value !== 'all') n += 1;
  if (assigneeFilter.value !== null) n += 1;
  if (labelFilter.value !== null) n += 1;
  if (dueFilter.value !== 'all') n += 1;
  if (hasConversationFilter.value) n += 1;
  return n;
});

// Snapshot of every filter that a saved view should restore. Kept as a
// plain object so persistence stays simple JSON.
const currentFilters = computed(() => ({
  priority: priorityFilter.value,
  assignee_id: assigneeFilter.value,
  label: labelFilter.value,
  due: dueFilter.value,
  has_conversation: hasConversationFilter.value,
  search: search.value,
}));

const applySavedView = filters => {
  if (!filters) return;
  if (filters.priority !== undefined) priorityFilter.value = filters.priority;
  if (filters.assignee_id !== undefined)
    assigneeFilter.value = filters.assignee_id;
  if (filters.label !== undefined) labelFilter.value = filters.label;
  if (filters.due !== undefined) dueFilter.value = filters.due;
  if (filters.has_conversation !== undefined) {
    hasConversationFilter.value = Boolean(filters.has_conversation);
  }
  if (filters.search !== undefined) search.value = filters.search;
};

const boardStats = computed(() => {
  const stagesList = stages.value;
  const allTasks = stagesList.flatMap(s => tasksByStage(s.id) || []);
  const total = allTasks.length;
  const wonStageIds = new Set(
    stagesList.filter(s => s.status_type === 'won').map(s => s.id)
  );
  const won = allTasks.filter(task =>
    wonStageIds.has(task.funnel_stage_id)
  ).length;
  const overdue = allTasks.filter(task => {
    if (!task.due_date) return false;
    return Number(task.due_date) * 1000 < Date.now();
  }).length;
  return {
    total,
    won,
    overdue,
    rate: total ? Math.round((won / total) * 100) : 0,
  };
});

const PRIORITY_OPTIONS = [
  { key: 'all', label: 'KANBAN.BOARD.FILTER.ALL' },
  { key: 'urgent', label: 'KANBAN.PRIORITY.URGENT' },
  { key: 'high', label: 'KANBAN.PRIORITY.HIGH' },
  { key: 'medium', label: 'KANBAN.PRIORITY.MEDIUM' },
  { key: 'low', label: 'KANBAN.PRIORITY.LOW' },
];

const loadTasks = async () => {
  try {
    await store.dispatch('kanbanTasks/getByFunnel', Number(props.funnelId));
  } catch (error) {
    useAlert(error?.message || t('KANBAN.TASK.LOAD_ERROR'));
  }
};

const ensureFunnel = async () => {
  if (funnel.value) return;
  try {
    await store.dispatch('funnels/show', Number(props.funnelId));
  } catch (error) {
    useAlert(error?.message || t('KANBAN.FUNNEL.LOAD_ERROR'));
  }
};

const openTaskFromRoute = id => {
  const task = store.getters['kanbanTasks/getTask'](id);
  if (!task) return;
  editingTask.value = task;
  defaultStageId.value = task.funnel_stage_id;
  showTaskModal.value = true;
};

const openCreateTask = stage => {
  editingTask.value = null;
  defaultStageId.value = stage?.id ?? stages.value[0]?.id ?? null;
  showTaskModal.value = true;
};

const openEditTask = task => {
  editingTask.value = task;
  defaultStageId.value = task.funnel_stage_id;
  showTaskModal.value = true;
};

const closeTaskModal = () => {
  showTaskModal.value = false;
  editingTask.value = null;
  defaultStageId.value = null;
  if (props.taskId) {
    router.replace(
      accountScopedRoute('kanban_board', { funnelId: props.funnelId })
    );
  }
};

onMounted(async () => {
  await ensureFunnel();
  await loadTasks();
  if (props.taskId) openTaskFromRoute(Number(props.taskId));
  // eslint-disable-next-line no-use-before-define
  document.addEventListener('keydown', onKeydown);
});

onBeforeUnmount(() => {
  // eslint-disable-next-line no-use-before-define
  document.removeEventListener('keydown', onKeydown);
});

watch(
  () => props.funnelId,
  async (next, prev) => {
    if (Number(next) === Number(prev)) return;
    await ensureFunnel();
    await loadTasks();
  }
);

watch(
  () => props.taskId,
  next => {
    if (!next) {
      closeTaskModal();
      return;
    }
    openTaskFromRoute(Number(next));
  }
);

// Salesforce-style: click on a Kanban card sends the operator straight
// to the linked conversation. Falls back to the task edit modal when the
// task has no conversation attached.
const onCardClick = task => {
  const conversation = (task.conversations || [])[0];
  if (conversation?.id) {
    router.push(
      accountScopedRoute('inbox_conversation', {
        conversation_id: conversation.id,
      })
    );
    return;
  }
  openEditTask(task);
};

// Selection handlers — toggle membership on click, clear with Esc or the
// floating bar's Clear button.
const onCardSelect = ({ taskId }) => {
  const next = new Set(selectedTaskIds.value);
  if (next.has(taskId)) next.delete(taskId);
  else next.add(taskId);
  selectedTaskIds.value = next;
};
const clearSelection = () => {
  selectedTaskIds.value = new Set();
};

// Inline title editing
const onCardTitleEdit = task => {
  inlineEditingTaskId.value = task.id;
};
const onCardTitleCancel = () => {
  inlineEditingTaskId.value = null;
};
const onCardTitleSubmit = async ({ taskId, title }) => {
  inlineEditingTaskId.value = null;
  try {
    await store.dispatch('kanbanTasks/update', { id: taskId, title });
  } catch (error) {
    useAlert(error?.message || t('KANBAN.TASK.SAVE_ERROR'));
    await loadTasks();
  }
};

// Bulk actions
const onBulkMove = async stageId => {
  const ids = Array.from(selectedTaskIds.value);
  try {
    await Promise.all(
      ids.map(id =>
        store.dispatch('kanbanTasks/move', {
          id,
          funnelId: Number(props.funnelId),
          funnelStageId: stageId,
          position: 1,
        })
      )
    );
    useAlert(t('KANBAN.BULK.MOVE_SUCCESS', { count: ids.length }));
    clearSelection();
  } catch (error) {
    useAlert(error?.message || t('KANBAN.BULK.ERROR'));
    await loadTasks();
  }
};

const onBulkAssign = async agentId => {
  const ids = Array.from(selectedTaskIds.value);
  try {
    await Promise.all(
      ids.map(id =>
        store.dispatch('kanbanTasks/update', {
          id,
          assignee_ids: agentId ? [agentId] : [],
        })
      )
    );
    useAlert(t('KANBAN.BULK.ASSIGN_SUCCESS', { count: ids.length }));
    clearSelection();
  } catch (error) {
    useAlert(error?.message || t('KANBAN.BULK.ERROR'));
    await loadTasks();
  }
};

const requestBulkDelete = () => {
  if (!selectedTaskIds.value.size) return;
  showBulkDeleteConfirm.value = true;
};
const cancelBulkDelete = () => {
  showBulkDeleteConfirm.value = false;
};
const confirmBulkDelete = async () => {
  const ids = Array.from(selectedTaskIds.value);
  showBulkDeleteConfirm.value = false;
  try {
    await Promise.all(
      ids.map(id =>
        store.dispatch('kanbanTasks/delete', {
          id,
          funnelId: Number(props.funnelId),
        })
      )
    );
    useAlert(t('KANBAN.BULK.DELETE_SUCCESS', { count: ids.length }));
    clearSelection();
  } catch (error) {
    useAlert(error?.message || t('KANBAN.BULK.ERROR'));
    await loadTasks();
  }
};

// Keyboard shortcuts. Bound at document scope so the user can interact from
// anywhere on the board view. Each guard avoids hijacking real text inputs.
const isEditableTarget = el =>
  el &&
  (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable);

function onKeydown(event) {
  if (event.key === 'Escape') {
    if (selectedTaskIds.value.size > 0) {
      event.preventDefault();
      clearSelection();
      return;
    }
    if (inlineEditingTaskId.value) {
      event.preventDefault();
      inlineEditingTaskId.value = null;
      return;
    }
    if (showTaskModal.value) {
      event.preventDefault();
      closeTaskModal();
    }
    return;
  }
  if (isEditableTarget(event.target)) return;

  if (event.key === '/' && !event.ctrlKey && !event.metaKey) {
    event.preventDefault();
    searchInputRef.value?.focus();
    return;
  }
  if (
    (event.key === 'n' || event.key === 'N') &&
    !event.metaKey &&
    !event.ctrlKey
  ) {
    event.preventDefault();
    openCreateTask(stages.value[0]);
  }
}

// SortableJS reorders the local array before this fires. If the API rejects
// the move we trigger a full reload to restore canonical state — cheaper than
// computing a per-card rollback.
const onTaskMoved = async ({ taskId, stageId, position }) => {
  const task = store.getters['kanbanTasks/getTask'](taskId);
  if (!task) return;
  if (
    task.funnel_stage_id === Number(stageId) &&
    task.position === Number(position)
  ) {
    return;
  }
  try {
    await store.dispatch('kanbanTasks/move', {
      id: taskId,
      funnelId: Number(props.funnelId),
      funnelStageId: stageId,
      position,
    });
  } catch (error) {
    useAlert(error?.message || t('KANBAN.TASK.MOVE_ERROR'));
    await loadTasks();
  }
};

const onTaskSubmit = async payload => {
  try {
    if (editingTask.value) {
      await store.dispatch('kanbanTasks/update', {
        id: editingTask.value.id,
        ...payload,
      });
      useAlert(t('KANBAN.TASK.UPDATE_SUCCESS'));
    } else {
      await store.dispatch('kanbanTasks/createInFunnel', {
        funnelId: Number(props.funnelId),
        payload,
      });
      useAlert(t('KANBAN.TASK.CREATE_SUCCESS'));
    }
    closeTaskModal();
  } catch (error) {
    useAlert(error?.message || t('KANBAN.TASK.SAVE_ERROR'));
  }
};

const requestDeleteTask = task => {
  taskPendingDelete.value = task;
  showDeleteConfirm.value = true;
};

const cancelDeleteTask = () => {
  taskPendingDelete.value = null;
  showDeleteConfirm.value = false;
};

const confirmDeleteTask = async () => {
  const task = taskPendingDelete.value;
  if (!task) return;
  try {
    await store.dispatch('kanbanTasks/delete', {
      id: task.id,
      funnelId: Number(props.funnelId),
    });
    useAlert(t('KANBAN.TASK.DELETE_SUCCESS'));
    cancelDeleteTask();
    closeTaskModal();
  } catch (error) {
    useAlert(error?.message || t('KANBAN.TASK.DELETE_ERROR'));
  }
};

const goBack = () => {
  router.push(accountScopedRoute('kanban_overview'));
};

const goToSettings = () => {
  router.push(
    accountScopedRoute('kanban_funnel_settings', {
      funnelId: Number(props.funnelId),
    })
  );
};
</script>

<template>
  <div class="flex flex-col h-full w-full bg-n-background">
    <!-- HERO HEADER: breadcrumb + name + inline stats + actions -->
    <header
      class="flex-shrink-0 px-7 pt-5 pb-4 border-b border-n-weak relative overflow-hidden"
    >
      <div
        class="absolute inset-0 bg-gradient-to-b from-n-alpha-1 to-transparent pointer-events-none"
      />
      <div class="relative flex items-start justify-between gap-4 mb-4">
        <div class="flex items-start gap-3 min-w-0 flex-1">
          <Button
            icon="i-lucide-arrow-left"
            size="xs"
            ghost
            slate
            :aria-label="t('KANBAN.BOARD.BACK')"
            class="mt-0.5"
            @click="goBack"
          />
          <div class="flex flex-col gap-1 min-w-0 flex-1">
            <nav class="flex items-center gap-1.5 text-[11px] text-n-slate-10">
              <button
                type="button"
                class="hover:text-n-slate-12 transition-colors uppercase tracking-[0.1em] font-medium"
                @click="goBack"
              >
                {{ t('KANBAN.OVERVIEW.TITLE') }}
              </button>
              <span class="i-lucide-chevron-right size-3 text-n-slate-9" />
              <span class="text-n-slate-11">{{ funnel?.name }}</span>
            </nav>
            <h1
              class="text-[20px] font-semibold text-n-slate-12 truncate tracking-tight leading-tight"
              :title="funnel?.name"
            >
              {{ funnel?.name || t('KANBAN.BOARD.LOADING') }}
            </h1>
            <p
              v-if="funnel?.description"
              class="text-[12px] text-n-slate-11 truncate"
            >
              {{ funnel.description }}
            </p>
          </div>
        </div>
        <div class="flex items-center gap-2 flex-shrink-0">
          <Button
            v-if="stages.length"
            icon="i-lucide-plus"
            size="sm"
            solid
            blue
            :label="t('KANBAN.BOARD.NEW_TASK')"
            @click="openCreateTask(stages[0])"
          />
          <Button
            v-if="isAdmin"
            icon="i-lucide-settings-2"
            size="sm"
            faded
            slate
            :aria-label="t('KANBAN.BOARD.SETTINGS')"
            @click="goToSettings"
          />
        </div>
      </div>

      <!-- Stats inline -->
      <div
        v-if="stages.length"
        class="relative flex items-center gap-6 text-[12px]"
      >
        <span class="inline-flex items-center gap-1.5">
          <span class="i-lucide-square-check-big size-3.5 text-n-slate-10" />
          <span class="text-n-slate-10">{{
            t('KANBAN.BOARD.STATS.TOTAL')
          }}</span>
          <span class="tabular-nums font-semibold text-n-slate-12">{{
            boardStats.total
          }}</span>
        </span>
        <span class="size-1 rounded-full bg-n-slate-7" />
        <span class="inline-flex items-center gap-1.5">
          <span class="i-lucide-trending-up size-3.5 text-n-teal-11" />
          <span class="text-n-slate-10">{{ t('KANBAN.BOARD.STATS.WON') }}</span>
          <span class="tabular-nums font-semibold text-n-teal-11">{{
            boardStats.won
          }}</span>
          <span class="tabular-nums font-semibold text-n-teal-11">
            {{ t('KANBAN.BOARD.STATS.RATE', { n: boardStats.rate }) }}
          </span>
        </span>
        <span class="size-1 rounded-full bg-n-slate-7" />
        <span
          class="inline-flex items-center gap-1.5"
          :class="boardStats.overdue ? 'text-n-ruby-11' : ''"
        >
          <span
            class="i-lucide-alarm-clock size-3.5"
            :class="boardStats.overdue ? 'text-n-ruby-11' : 'text-n-slate-10'"
          />
          <span
            :class="boardStats.overdue ? 'text-n-ruby-11' : 'text-n-slate-10'"
          >
            {{ t('KANBAN.BOARD.STATS.OVERDUE') }}
          </span>
          <span
            class="tabular-nums font-semibold"
            :class="boardStats.overdue ? 'text-n-ruby-11' : 'text-n-slate-12'"
          >
            {{ boardStats.overdue }}
          </span>
        </span>
      </div>
    </header>

    <!-- Toolbar: search + priority filter -->
    <div
      v-if="stages.length"
      class="flex-shrink-0 flex items-center gap-3 px-7 py-3 border-b border-n-weak"
    >
      <div
        class="flex-1 max-w-sm flex items-center gap-2 px-3 py-1.5 rounded-lg bg-n-alpha-1 ring-1 ring-inset ring-n-weak focus-within:ring-n-slate-7 transition"
      >
        <span class="i-lucide-search size-3.5 text-n-slate-10 flex-shrink-0" />
        <input
          ref="searchInputRef"
          v-model="search"
          type="text"
          :placeholder="t('KANBAN.BOARD.SEARCH_PLACEHOLDER')"
          class="flex-1 bg-transparent outline-none text-[13px] text-n-slate-12 placeholder:text-n-slate-10"
        />
        <kbd
          v-if="!search"
          class="hidden md:inline-flex items-center justify-center size-5 rounded text-[10px] font-mono text-n-slate-10 bg-n-alpha-2 ring-1 ring-inset ring-n-weak"
        >
          {{ '/' }}
        </kbd>
        <button
          v-if="search"
          type="button"
          class="text-n-slate-10 hover:text-n-slate-12"
          @click="search = ''"
        >
          <span class="i-lucide-x size-3.5" />
        </button>
      </div>
      <div
        class="flex items-center gap-1 p-0.5 rounded-lg bg-n-alpha-1 ring-1 ring-inset ring-n-weak"
      >
        <button
          v-for="opt in PRIORITY_OPTIONS"
          :key="opt.key"
          type="button"
          class="px-2.5 py-1 rounded-md text-[11px] font-medium transition-colors"
          :class="
            priorityFilter === opt.key
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="priorityFilter = opt.key"
        >
          {{ t(opt.label) }}
        </button>
      </div>

      <!-- Assignee filter -->
      <select
        v-model="assigneeFilter"
        class="px-2.5 py-1.5 rounded-lg bg-n-alpha-1 ring-1 ring-inset ring-n-weak text-[11px] font-medium text-n-slate-12 focus:outline-none focus:ring-n-teal-7 cursor-pointer"
      >
        <option :value="null">
          {{ t('KANBAN.BOARD.FILTER.ALL_ASSIGNEES') }}
        </option>
        <option
          v-for="agent in agentsList || []"
          :key="agent.id"
          :value="agent.id"
        >
          {{ agent.name }}
        </option>
      </select>

      <!-- Label filter -->
      <select
        v-model="labelFilter"
        class="px-2.5 py-1.5 rounded-lg bg-n-alpha-1 ring-1 ring-inset ring-n-weak text-[11px] font-medium text-n-slate-12 focus:outline-none focus:ring-n-teal-7 cursor-pointer"
      >
        <option :value="null">
          {{ t('KANBAN.BOARD.FILTER.ALL_LABELS') }}
        </option>
        <option
          v-for="label in labelsList || []"
          :key="label.id"
          :value="label.title"
        >
          {{ label.title }}
        </option>
      </select>

      <!-- Due window filter -->
      <select
        v-model="dueFilter"
        class="px-2.5 py-1.5 rounded-lg bg-n-alpha-1 ring-1 ring-inset ring-n-weak text-[11px] font-medium text-n-slate-12 focus:outline-none focus:ring-n-teal-7 cursor-pointer"
      >
        <option value="all">{{ t('KANBAN.BOARD.FILTER.DUE_ALL') }}</option>
        <option value="overdue">
          {{ t('KANBAN.BOARD.FILTER.DUE_OVERDUE') }}
        </option>
        <option value="today">{{ t('KANBAN.BOARD.FILTER.DUE_TODAY') }}</option>
        <option value="week">{{ t('KANBAN.BOARD.FILTER.DUE_WEEK') }}</option>
        <option value="none">{{ t('KANBAN.BOARD.FILTER.DUE_NONE') }}</option>
      </select>

      <!-- Has-conversation toggle -->
      <button
        type="button"
        class="inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg ring-1 ring-inset text-[11px] font-medium transition-colors"
        :class="
          hasConversationFilter
            ? 'bg-n-teal-3 ring-n-teal-7 text-n-teal-11'
            : 'bg-n-alpha-1 ring-n-weak text-n-slate-11 hover:text-n-slate-12'
        "
        :aria-pressed="hasConversationFilter"
        @click="hasConversationFilter = !hasConversationFilter"
      >
        <span class="i-lucide-message-square size-3.5" aria-hidden="true" />
        {{ t('KANBAN.BOARD.FILTER.HAS_CONVERSATION') }}
      </button>

      <KanbanSavedViews
        :funnel-id="props.funnelId"
        :current-filters="currentFilters"
        :active-filter-count="activeFilterCount"
        @apply="applySavedView"
      />

      <!-- Group by (swimlanes) -->
      <select
        v-model="groupBy"
        class="px-2.5 py-1.5 rounded-lg bg-n-alpha-1 ring-1 ring-inset ring-n-weak text-[11px] font-medium text-n-slate-12 focus:outline-none focus:ring-n-teal-7 cursor-pointer"
        :title="t('KANBAN.BOARD.SWIMLANES.TITLE')"
      >
        <option v-for="opt in GROUP_BY_OPTIONS" :key="opt" :value="opt">
          {{ t(`KANBAN.BOARD.SWIMLANES.${opt.toUpperCase()}`) }}
        </option>
      </select>

      <button
        v-if="activeFilterCount > 0 || search"
        type="button"
        class="text-[11px] font-medium text-n-slate-11 hover:text-n-slate-12 transition-colors cursor-pointer"
        @click="clearAllFilters"
      >
        {{ t('KANBAN.BOARD.FILTER.CLEAR') }}
        <span v-if="activeFilterCount" class="text-n-teal-11 tabular-nums">
          ({{ activeFilterCount }})
        </span>
      </button>
    </div>

    <section
      v-if="funnelUiFlags.isFetching || taskUiFlags.isFetching"
      class="flex-1 flex items-center justify-center"
    >
      <span
        class="i-lucide-loader-circle size-6 animate-spin text-n-slate-10"
      />
    </section>

    <section
      v-else-if="!funnel"
      class="flex-1 flex items-center justify-center text-sm text-n-slate-11"
    >
      {{ t('KANBAN.BOARD.NOT_FOUND') }}
    </section>

    <section
      v-else-if="!stages.length"
      class="flex-1 flex flex-col items-center justify-center gap-3 px-8 text-center"
    >
      <div
        class="size-14 rounded-2xl bg-n-alpha-1 flex items-center justify-center"
      >
        <span class="i-lucide-layers size-6 text-n-slate-10" />
      </div>
      <div class="flex flex-col gap-1 max-w-sm">
        <h2 class="text-base font-medium text-n-slate-12">
          {{ t('KANBAN.BOARD.NO_STAGES_TITLE') }}
        </h2>
        <p class="text-sm text-n-slate-11">
          {{ t('KANBAN.BOARD.NO_STAGES_DESCRIPTION') }}
        </p>
      </div>
      <Button
        v-if="isAdmin"
        icon="i-lucide-settings-2"
        size="sm"
        :label="t('KANBAN.BOARD.OPEN_SETTINGS')"
        @click="goToSettings"
      />
    </section>

    <section v-else class="flex-1 overflow-auto">
      <!-- Classic single-row layout. -->
      <div
        v-if="groupBy === 'none'"
        class="flex items-stretch gap-4 px-7 py-5 h-full min-w-min"
      >
        <KanbanColumn
          v-for="stage in stages"
          :key="stage.id"
          :stage="stage"
          :tasks="tasksByStageFiltered(stage.id)"
          :funnel-name="funnel?.name || ''"
          :can-mutate="canMutate"
          :selected-task-ids="selectedTaskIds"
          :inline-editing-task-id="inlineEditingTaskId"
          @card-click="onCardClick"
          @card-select="onCardSelect"
          @card-title-edit="onCardTitleEdit"
          @card-title-submit="onCardTitleSubmit"
          @card-title-cancel="onCardTitleCancel"
          @task-moved="onTaskMoved"
          @add-task="openCreateTask"
        />
      </div>

      <!-- Swimlanes layout — one horizontal row of columns per group key. -->
      <div v-else class="flex flex-col gap-6 px-7 py-5 min-w-min">
        <article
          v-for="lane in lanes"
          :key="lane.key"
          class="flex flex-col gap-3"
        >
          <header
            class="flex items-center gap-3 px-2 py-1.5 rounded-lg bg-n-alpha-1 ring-1 ring-inset ring-n-weak sticky left-0 max-w-fit"
          >
            <span
              class="inline-flex items-center justify-center size-6 rounded-md bg-n-teal-3 text-n-teal-11 text-[10px] font-bold uppercase tracking-wider"
            >
              <span class="i-lucide-rows-3 size-3.5" aria-hidden="true" />
            </span>
            <span class="text-[12px] font-semibold text-n-slate-12 truncate">
              {{ lane.label }}
            </span>
            <span class="text-[11px] tabular-nums text-n-slate-11 font-medium">
              {{ lane.count }}
            </span>
          </header>
          <div class="flex items-stretch gap-4">
            <KanbanColumn
              v-for="stage in stages"
              :key="`${lane.key}-${stage.id}`"
              :stage="stage"
              :tasks="tasksByStageInLane(stage.id, lane.key)"
              :funnel-name="funnel?.name || ''"
              :can-mutate="canMutate"
              :selected-task-ids="selectedTaskIds"
              :inline-editing-task-id="inlineEditingTaskId"
              @card-click="onCardClick"
              @card-select="onCardSelect"
              @card-title-edit="onCardTitleEdit"
              @card-title-submit="onCardTitleSubmit"
              @card-title-cancel="onCardTitleCancel"
              @task-moved="onTaskMoved"
              @add-task="openCreateTask"
            />
          </div>
        </article>
        <p
          v-if="!lanes.length"
          class="text-center text-sm text-n-slate-11 py-12"
        >
          {{ t('KANBAN.BOARD.SWIMLANES.EMPTY') }}
        </p>
      </div>
    </section>

    <KanbanBulkActionBar
      :count="selectedTaskIds.size"
      :stages="stages"
      :agents="agentsList || []"
      @move="onBulkMove"
      @assign="onBulkAssign"
      @delete="requestBulkDelete"
      @clear="clearSelection"
    />

    <woot-delete-modal
      v-model:show="showBulkDeleteConfirm"
      :on-close="cancelBulkDelete"
      :on-confirm="confirmBulkDelete"
      :title="t('KANBAN.BULK.DELETE_CONFIRM_TITLE')"
      :message="
        t('KANBAN.BULK.DELETE_CONFIRM_MESSAGE', { count: selectedTaskIds.size })
      "
      :confirm-text="t('KANBAN.BULK.DELETE')"
      :reject-text="t('KANBAN.TASK.CANCEL')"
    />

    <KanbanTaskDrawer v-model:show="showTaskModal" @close="closeTaskModal">
      <TaskFormModal
        v-if="showTaskModal && funnel"
        :task="editingTask"
        :funnel="funnel"
        :default-stage-id="defaultStageId"
        @submit="onTaskSubmit"
        @close="closeTaskModal"
        @delete="requestDeleteTask"
      />
    </KanbanTaskDrawer>

    <woot-delete-modal
      v-model:show="showDeleteConfirm"
      :on-close="cancelDeleteTask"
      :on-confirm="confirmDeleteTask"
      :title="t('KANBAN.TASK.DELETE_CONFIRM_TITLE')"
      :message="t('KANBAN.TASK.DELETE_CONFIRM_MESSAGE')"
      :confirm-text="t('KANBAN.TASK.DELETE')"
      :reject-text="t('KANBAN.TASK.CANCEL')"
    />
  </div>
</template>
