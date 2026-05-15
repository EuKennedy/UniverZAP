<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import { useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'shared/components/Spinner.vue';
import TaskFormModal from 'dashboard/routes/dashboard/kanban/components/TaskFormModal.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const PRIORITY_DOT = {
  urgent: 'bg-n-ruby-9',
  high: 'bg-n-amber-9',
  medium: 'bg-n-blue-9',
  low: 'bg-n-slate-8',
  none: 'bg-transparent',
};

const STATUS_BADGE = {
  active: 'bg-n-blue-9/15 text-n-blue-11',
  won: 'bg-n-teal-9/15 text-n-teal-11',
  lost: 'bg-n-ruby-9/15 text-n-ruby-11',
};

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const tasksByConversation = useMapGetter('kanbanTasks/getTasksByConversation');
const tasks = computed(
  () => tasksByConversation.value(props.conversationId) || []
);

const funnels = useMapGetter('funnels/getFunnels');
const uiFlags = useMapGetter('kanbanTasks/getUIFlags');

const isLoading = computed(() => uiFlags.value.isFetchingForConversation);
const isLinking = computed(() => uiFlags.value.isLinking);

const loadedFunnels = ref(false);
const showLinkModal = ref(false);
const showCreateModal = ref(false);
const linkFunnelId = ref(null);
const linkTaskId = ref(null);
const createFunnelId = ref(null);

const ensureFunnels = async () => {
  if (loadedFunnels.value) return;
  try {
    await store.dispatch('funnels/get');
    loadedFunnels.value = true;
  } catch (e) {
    /* surfaced via uiFlags */
  }
};

const fetchTasksForLinking = async funnelId => {
  if (!funnelId) return;
  try {
    await store.dispatch('kanbanTasks/getByFunnel', funnelId);
  } catch (e) {
    useAlert(e?.message || t('KANBAN.TASK.MOVE_ERROR'));
  }
};

const tasksForLinkFunnel = computed(() => {
  if (!linkFunnelId.value) return [];
  const all = store.getters['kanbanTasks/getTasks'](linkFunnelId.value);
  const linkedIds = new Set(tasks.value.map(tk => tk.id));
  return all.filter(tk => !linkedIds.has(tk.id));
});

const createFunnel = computed(
  () => funnels.value.find(f => f.id === Number(createFunnelId.value)) || null
);

watch(linkFunnelId, async newId => {
  linkTaskId.value = null;
  if (newId) await fetchTasksForLinking(newId);
});

const loadInitial = async () => {
  try {
    await store.dispatch('kanbanTasks/getByConversation', props.conversationId);
  } catch (e) {
    /* swallow — empty state */
  }
};

watch(
  () => props.conversationId,
  newId => {
    if (newId) loadInitial();
  },
  { immediate: true }
);

const openLinkModal = async () => {
  showLinkModal.value = true;
  await ensureFunnels();
  if (!linkFunnelId.value && funnels.value.length) {
    linkFunnelId.value = funnels.value[0].id;
  }
};

const closeLinkModal = () => {
  showLinkModal.value = false;
  linkTaskId.value = null;
};

const onLink = async () => {
  if (!linkTaskId.value) return;
  try {
    await store.dispatch('kanbanTasks/attachConversation', {
      taskId: linkTaskId.value,
      conversationId: props.conversationId,
    });
    useAlert(t('KANBAN.TASK.LINK_SUCCESS'));
    closeLinkModal();
  } catch (e) {
    useAlert(e?.message || t('KANBAN.TASK.LINK_ERROR'));
  }
};

const onUnlink = async task => {
  try {
    await store.dispatch('kanbanTasks/detachConversation', {
      taskId: task.id,
      conversationId: props.conversationId,
    });
    useAlert(t('KANBAN.TASK.UNLINK_SUCCESS'));
  } catch (e) {
    useAlert(e?.message || t('KANBAN.TASK.UNLINK_ERROR'));
  }
};

const openCreateModal = async () => {
  await ensureFunnels();
  if (!funnels.value.length) {
    useAlert(t('KANBAN.TASK.NO_FUNNELS'));
    return;
  }
  createFunnelId.value = funnels.value[0].id;
  showCreateModal.value = true;
};

const closeCreateModal = () => {
  showCreateModal.value = false;
};

const onCreate = async payload => {
  try {
    const created = await store.dispatch('kanbanTasks/createInFunnel', {
      funnelId: createFunnelId.value,
      payload,
    });
    await store.dispatch('kanbanTasks/attachConversation', {
      taskId: created.id,
      conversationId: props.conversationId,
    });
    useAlert(t('KANBAN.TASK.CREATE_SUCCESS'));
    closeCreateModal();
  } catch (e) {
    useAlert(e?.message || t('KANBAN.TASK.CREATE_ERROR'));
  }
};

const stageFor = task => {
  if (!task?.funnel_id || !task?.funnel_stage_id) return null;
  const funnel = funnels.value.find(f => f.id === task.funnel_id);
  if (!funnel?.stages) return null;
  return funnel.stages.find(s => s.id === task.funnel_stage_id) || null;
};

const formatDue = ts => {
  if (!ts) return null;
  const date = new Date(ts * 1000);
  const diffDays = Math.round(
    (date.getTime() - Date.now()) / (1000 * 60 * 60 * 24)
  );
  if (diffDays === 0)
    return { text: t('KANBAN.CARD.DUE_TODAY'), overdue: false };
  if (diffDays === 1)
    return { text: t('KANBAN.CARD.DUE_TOMORROW'), overdue: false };
  if (diffDays === -1)
    return { text: t('KANBAN.CARD.DUE_YESTERDAY'), overdue: true };
  if (diffDays > 1)
    return {
      text: t('KANBAN.CARD.DUE_IN_DAYS', { n: diffDays }),
      overdue: false,
    };
  return {
    text: t('KANBAN.CARD.DUE_OVERDUE_DAYS', { n: -diffDays }),
    overdue: true,
  };
};

const goToTask = task => {
  router.push(
    accountScopedRoute('kanban_task_show', {
      funnelId: task.funnel_id,
      taskId: task.id,
    })
  );
};
</script>

<template>
  <div class="flex flex-col gap-2 px-3 pt-1 pb-3">
    <div class="flex items-center justify-end gap-1">
      <Button
        xs
        slate
        faded
        icon="i-lucide-link"
        :label="t('KANBAN.TASK.LINK_EXISTING')"
        @click="openLinkModal"
      />
      <Button
        xs
        icon="i-lucide-plus"
        :label="t('KANBAN.TASK.NEW_TITLE')"
        @click="openCreateModal"
      />
    </div>

    <div
      v-if="isLoading && !tasks.length"
      class="flex items-center justify-center py-6"
    >
      <Spinner />
    </div>

    <div
      v-else-if="!tasks.length"
      class="flex flex-col items-center justify-center gap-2 py-6 text-center"
    >
      <span class="i-lucide-kanban-square size-6 text-n-slate-9" />
      <p class="text-xs text-n-slate-11 max-w-[200px]">
        {{ t('KANBAN.TASK.CONVERSATION_EMPTY') }}
      </p>
    </div>

    <ul v-else class="flex flex-col gap-2">
      <li
        v-for="task in tasks"
        :key="task.id"
        class="group flex flex-col gap-1.5 p-2.5 rounded-lg bg-n-solid-1 border border-n-weak hover:border-n-slate-7 transition-colors cursor-pointer"
        @click="goToTask(task)"
      >
        <div class="flex items-start justify-between gap-2">
          <span class="text-xs font-mono text-n-slate-10">
            #{{ task.display_id }}
          </span>
          <button
            type="button"
            class="opacity-0 group-hover:opacity-100 transition-opacity text-n-slate-10 hover:text-n-ruby-10"
            :title="t('KANBAN.TASK.UNLINK')"
            @click.stop="onUnlink(task)"
          >
            <span class="i-lucide-link-2-off size-3.5" />
          </button>
        </div>
        <p
          class="text-sm font-medium text-n-slate-12 leading-snug line-clamp-2"
        >
          {{ task.title }}
        </p>
        <div class="flex flex-wrap items-center gap-2 text-xs text-n-slate-11">
          <span
            v-if="stageFor(task)"
            class="inline-flex items-center px-1.5 py-0.5 rounded-md text-[10px] font-medium"
            :class="
              STATUS_BADGE[stageFor(task).status_type] || STATUS_BADGE.active
            "
          >
            {{ stageFor(task).name }}
          </span>
          <span
            v-if="task.priority && task.priority !== 'none'"
            class="inline-flex items-center gap-1"
          >
            <span
              class="size-1.5 rounded-full"
              :class="PRIORITY_DOT[task.priority]"
            />
            {{ t(`KANBAN.PRIORITY.${task.priority.toUpperCase()}`) }}
          </span>
          <span
            v-if="formatDue(task.due_date)"
            class="inline-flex items-center gap-1"
            :class="{ 'text-n-ruby-10': formatDue(task.due_date).overdue }"
          >
            <span class="i-lucide-calendar-clock size-3" />
            {{ formatDue(task.due_date).text }}
          </span>
        </div>
      </li>
    </ul>

    <woot-modal v-model:show="showLinkModal" :on-close="closeLinkModal">
      <div class="flex flex-col w-full">
        <woot-modal-header
          :header-title="t('KANBAN.TASK.LINK_TITLE')"
          :header-content="t('KANBAN.TASK.LINK_DESCRIPTION')"
        />
        <div class="flex flex-col gap-4 px-6 py-5">
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('KANBAN.TASK.FORM.FUNNEL_LABEL') }}
            </label>
            <select
              v-model="linkFunnelId"
              class="px-3 py-2 rounded-md border border-n-weak bg-n-background text-sm text-n-slate-12 focus:outline-none focus:border-n-brand"
            >
              <option
                v-for="funnel in funnels"
                :key="funnel.id"
                :value="funnel.id"
              >
                {{ funnel.name }}
              </option>
            </select>
          </div>
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('KANBAN.TASK.LINK_PICK_TASK') }}
            </label>
            <select
              v-model="linkTaskId"
              :disabled="!tasksForLinkFunnel.length"
              class="px-3 py-2 rounded-md border border-n-weak bg-n-background text-sm text-n-slate-12 focus:outline-none focus:border-n-brand disabled:opacity-60"
            >
              <option :value="null" disabled>
                {{
                  tasksForLinkFunnel.length
                    ? t('KANBAN.TASK.LINK_PICK_TASK_PLACEHOLDER')
                    : t('KANBAN.TASK.LINK_NO_TASKS')
                }}
              </option>
              <option
                v-for="task in tasksForLinkFunnel"
                :key="task.id"
                :value="task.id"
              >
                #{{ task.display_id }} — {{ task.title }}
              </option>
            </select>
          </div>
          <footer class="flex items-center justify-end gap-2 pt-1">
            <Button
              faded
              slate
              type="button"
              :label="t('KANBAN.TASK.CANCEL')"
              @click="closeLinkModal"
            />
            <Button
              type="button"
              :label="t('KANBAN.TASK.LINK_CONFIRM')"
              :disabled="!linkTaskId || isLinking"
              :is-loading="isLinking"
              @click="onLink"
            />
          </footer>
        </div>
      </div>
    </woot-modal>

    <woot-modal v-model:show="showCreateModal" :on-close="closeCreateModal">
      <div class="flex flex-col w-full">
        <div v-if="funnels.length > 1" class="px-6 pt-5 -mb-2">
          <label
            class="text-sm font-medium text-n-slate-12 flex flex-col gap-1.5"
          >
            {{ t('KANBAN.TASK.FORM.FUNNEL_LABEL') }}
            <select
              v-model="createFunnelId"
              class="px-3 py-2 rounded-md border border-n-weak bg-n-background text-sm text-n-slate-12 focus:outline-none focus:border-n-brand"
            >
              <option
                v-for="funnel in funnels"
                :key="funnel.id"
                :value="funnel.id"
              >
                {{ funnel.name }}
              </option>
            </select>
          </label>
        </div>
        <TaskFormModal
          v-if="createFunnel"
          :funnel="createFunnel"
          :default-stage-id="createFunnel.stages?.[0]?.id"
          @submit="onCreate"
          @close="closeCreateModal"
        />
      </div>
    </woot-modal>
  </div>
</template>
