<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';
import KanbanColumn from '../components/KanbanColumn.vue';
import TaskFormModal from '../components/TaskFormModal.vue';

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

const draggingTaskId = ref(null);
const showTaskModal = ref(false);
const editingTask = ref(null);
const defaultStageId = ref(null);
const showDeleteConfirm = ref(false);
const taskPendingDelete = ref(null);
const search = ref('');
const priorityFilter = ref('all');

const tasksByStageFiltered = stageId => {
  const all = tasksByStage(stageId) || [];
  const q = search.value.trim().toLowerCase();
  return all.filter(task => {
    if (
      priorityFilter.value !== 'all' &&
      task.priority !== priorityFilter.value
    ) {
      return false;
    }
    if (!q) return true;
    const title = (task.title || '').toLowerCase();
    const contactName = (task.contacts?.[0]?.name || '').toLowerCase();
    return title.includes(q) || contactName.includes(q);
  });
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

const onTaskDragstart = (task, event) => {
  draggingTaskId.value = task.id;
  if (event?.dataTransfer) {
    event.dataTransfer.effectAllowed = 'move';
    try {
      event.dataTransfer.setData('text/plain', String(task.id));
    } catch (_) {
      /* noop */
    }
  }
};

const onTaskDragend = () => {
  draggingTaskId.value = null;
};

const onTaskDrop = async ({ stageId, taskId: droppedId, position }) => {
  draggingTaskId.value = null;
  const task = store.getters['kanbanTasks/getTask'](droppedId);
  if (!task) return;
  if (
    task.funnel_stage_id === Number(stageId) &&
    task.position === Number(position)
  ) {
    return;
  }
  try {
    await store.dispatch('kanbanTasks/move', {
      id: droppedId,
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
          v-model="search"
          type="text"
          :placeholder="t('KANBAN.BOARD.SEARCH_PLACEHOLDER')"
          class="flex-1 bg-transparent outline-none text-[13px] text-n-slate-12 placeholder:text-n-slate-10"
        />
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

    <section v-else class="flex-1 overflow-x-auto overflow-y-hidden">
      <div class="flex items-stretch gap-4 px-7 py-5 h-full min-w-min">
        <KanbanColumn
          v-for="stage in stages"
          :key="stage.id"
          :stage="stage"
          :tasks="tasksByStageFiltered(stage.id)"
          :dragging-task-id="draggingTaskId"
          :can-mutate="canMutate"
          @card-click="onCardClick"
          @task-dragstart="onTaskDragstart"
          @task-dragend="onTaskDragend"
          @task-drop="onTaskDrop"
          @add-task="openCreateTask"
        />
      </div>
    </section>

    <woot-modal
      v-model:show="showTaskModal"
      :on-close="closeTaskModal"
      size="medium"
    >
      <TaskFormModal
        v-if="showTaskModal && funnel"
        :task="editingTask"
        :funnel="funnel"
        :default-stage-id="defaultStageId"
        @submit="onTaskSubmit"
        @close="closeTaskModal"
        @delete="requestDeleteTask"
      />
    </woot-modal>

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
