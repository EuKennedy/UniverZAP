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

const onCardClick = task => openEditTask(task);

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
    <header
      class="flex items-center justify-between flex-shrink-0 gap-4 px-6 py-4 border-b border-n-weak"
    >
      <div class="flex items-center gap-2.5 min-w-0">
        <Button
          icon="i-lucide-arrow-left"
          size="xs"
          ghost
          slate
          :aria-label="t('KANBAN.BOARD.BACK')"
          @click="goBack"
        />
        <nav
          class="flex items-center gap-1.5 text-[12px] text-n-slate-11 flex-shrink-0"
        >
          <button
            type="button"
            class="hover:text-n-slate-12 transition-colors"
            @click="goBack"
          >
            {{ t('KANBAN.OVERVIEW.TITLE') }}
          </button>
          <span class="i-lucide-chevron-right size-3 text-n-slate-9" />
        </nav>
        <div class="flex flex-col gap-0.5 min-w-0">
          <h1
            class="text-base font-semibold text-n-slate-12 truncate tracking-tight"
            :title="funnel?.name"
          >
            {{ funnel?.name || t('KANBAN.BOARD.LOADING') }}
          </h1>
          <p
            v-if="funnel?.description"
            class="text-[11px] text-n-slate-11 truncate"
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
          :label="t('KANBAN.BOARD.NEW_TASK')"
          @click="openCreateTask(stages[0])"
        />
        <Button
          v-if="isAdmin"
          icon="i-lucide-settings-2"
          size="sm"
          faded
          slate
          :label="t('KANBAN.BOARD.SETTINGS')"
          @click="goToSettings"
        />
      </div>
    </header>

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
      <div class="flex items-stretch gap-4 px-6 py-5 h-full min-w-min">
        <KanbanColumn
          v-for="stage in stages"
          :key="stage.id"
          :stage="stage"
          :tasks="tasksByStage(stage.id)"
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
