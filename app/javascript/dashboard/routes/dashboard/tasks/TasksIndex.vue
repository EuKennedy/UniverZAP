<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';

import TasksHeader from './components/TasksHeader.vue';
import TasksFilters from './components/TasksFilters.vue';
import TasksList from './components/TasksList.vue';
import TasksSkeleton from './components/TasksSkeleton.vue';
import TaskCreateModal from './components/TaskCreateModal.vue';
import TaskDetailDrawer from './components/TaskDetailDrawer.vue';
import TaskSavedViewsList from './components/TaskSavedViewsList.vue';
import TasksBulkActionBar from './components/TasksBulkActionBar.vue';
import TeamWorkloadDashboard from './components/TeamWorkloadDashboard.vue';
import TasksReports from './components/TasksReports.vue';
import TeamChatPanel from './components/teamChat/TeamChatPanel.vue';
import TeamChatCreateChannelModal from './components/teamChat/TeamChatCreateChannelModal.vue';

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();
const { uiSettings, updateUISettings } = useUISettings();

const tasks = useMapGetter('tasks/getTasks');
const filters = useMapGetter('tasks/getFilters');
const uiFlags = useMapGetter('tasks/getUiFlags');
const mineCount = useMapGetter('tasks/getMineCount');
const overdueCount = useMapGetter('tasks/getOverdueCount');
const meta = useMapGetter('tasks/getMeta');
const savedViews = useMapGetter('taskViews/getViews');
const currentUser = useMapGetter('getCurrentUser');
const chatChannels = useMapGetter('teamChat/getChannels');
const activeChatChannelId = useMapGetter('teamChat/getActiveChannelId');
const activeChatChannel = useMapGetter('teamChat/getActiveChannel');

const showCreateModal = ref(false);
const groupBy = ref('urgency');
const activeQuickFilter = ref(null);
const activeView = ref('list');
const activeViewId = ref(null);
const selectedIds = ref([]);
const isBulkBusy = ref(false);
const showChannelModal = ref(false);
const editingChannel = ref(null);

const TABS = [
  { key: 'mine', labelKey: 'TASKS.TABS.MINE', scope: 'mine' },
  {
    key: 'created_by_me',
    labelKey: 'TASKS.TABS.CREATED_BY_ME',
    scope: 'created_by_me',
  },
  { key: 'team', labelKey: 'TASKS.TABS.TEAM', scope: 'team' },
  { key: 'all', labelKey: 'TASKS.TABS.ALL', scope: 'all' },
];

const ADMIN_VIEWS = [
  { key: 'team_board', labelKey: 'TASKS.VIEWS.TEAM_BOARD' },
  { key: 'reports', labelKey: 'TASKS.VIEWS.REPORTS' },
];

const QUICK_FILTERS = [
  {
    key: 'overdue',
    labelKey: 'TASKS.QUICK_FILTERS.OVERDUE',
    icon: 'i-lucide-alarm-clock',
  },
  {
    key: 'today',
    labelKey: 'TASKS.QUICK_FILTERS.TODAY',
    icon: 'i-lucide-calendar-days',
  },
  {
    key: 'this_week',
    labelKey: 'TASKS.QUICK_FILTERS.THIS_WEEK',
    icon: 'i-lucide-calendar',
  },
];

const isAdmin = computed(() => currentUser.value?.role === 'administrator');
const activeScope = computed(() => filters.value.scope || 'mine');
const settingsKey = computed(() => `tasks_filters_${activeScope.value}`);

const tabCounts = computed(() => ({
  mine: mineCount.value,
  team: meta.value?.count || 0,
  all: meta.value?.count || 0,
  created_by_me: meta.value?.count || 0,
}));

const refresh = () => {
  store.dispatch('tasks/fetch');
};

const persistFilters = patch => {
  const next = { ...filters.value, ...patch };
  updateUISettings({ [settingsKey.value]: next });
};

const setScope = scope => {
  if (filters.value.scope === scope) return;
  activeQuickFilter.value = null;
  store.dispatch('tasks/setFilters', { scope, due_before: null });
  refresh();
};

const updateFilters = patch => {
  store.dispatch('tasks/setFilters', patch);
  persistFilters(patch);
  refresh();
};

const clearFilters = () => {
  activeQuickFilter.value = null;
  activeViewId.value = null;
  const cleared = {
    status: null,
    urgency: null,
    assignee_id: null,
    due_before: null,
    q: null,
  };
  store.dispatch('tasks/setFilters', cleared);
  persistFilters(cleared);
  refresh();
};

const applyQuickFilter = key => {
  activeQuickFilter.value = activeQuickFilter.value === key ? null : key;
  if (!activeQuickFilter.value) {
    updateFilters({ due_before: null });
    return;
  }
  const now = new Date();
  let isoBoundary = null;
  if (key === 'overdue') {
    isoBoundary = now.toISOString();
  } else if (key === 'today') {
    const endOfDay = new Date(now);
    endOfDay.setHours(23, 59, 59, 999);
    isoBoundary = endOfDay.toISOString();
  } else if (key === 'this_week') {
    const endOfWeek = new Date(now);
    endOfWeek.setDate(now.getDate() + (7 - now.getDay()));
    endOfWeek.setHours(23, 59, 59, 999);
    isoBoundary = endOfWeek.toISOString();
  }
  updateFilters({ due_before: isoBoundary });
};

const isFiltered = computed(() => {
  const f = filters.value || {};
  return Boolean(f.status || f.urgency || f.assignee_id || f.due_before || f.q);
});

const handleCreate = async payload => {
  try {
    const created = await store.dispatch('tasks/create', payload);
    useAlert(t('TASKS.CREATE.SUCCESS'));
    showCreateModal.value = false;
    if (created?.id) {
      router.replace({
        name: 'tasks',
        query: { ...route.query, task: String(created.id) },
      });
    }
  } catch (error) {
    useAlert(error?.message || t('TASKS.CREATE.ERROR'));
  }
};

const handleToggle = async task => {
  if (['done', 'cancelled'].includes(task.status)) {
    await store.dispatch('tasks/update', {
      id: task.id,
      status: 'open',
      completed_at: null,
    });
  } else {
    await store.dispatch('tasks/complete', task.id);
  }
};

const openTask = task => {
  router.replace({
    name: 'tasks',
    query: { ...route.query, task: String(task.id) },
  });
};

const closeDrawer = () => {
  const nextQuery = { ...route.query };
  delete nextQuery.task;
  router.replace({ name: 'tasks', query: nextQuery });
};

const handleDelete = async task => {
  if (!window.confirm(t('TASKS.DETAIL.ACTIONS.DELETE_CONFIRM'))) return;
  try {
    await store.dispatch('tasks/delete', task.id);
    useAlert(t('TASKS.DETAIL.DELETE_SUCCESS'));
  } catch (error) {
    useAlert(error?.message || t('TASKS.DETAIL.DELETE_ERROR'));
  }
};

const drawerTaskId = computed(() =>
  route.query.task ? Number(route.query.task) : null
);

const currentTask = computed(() => {
  if (!drawerTaskId.value) return null;
  return tasks.value.find(task => task.id === drawerTaskId.value) || null;
});

const handleSelectionChange = ids => {
  selectedIds.value = ids;
};

const runBulk = async (action, payload = {}) => {
  if (!selectedIds.value.length) return;
  isBulkBusy.value = true;
  try {
    const result = await store.dispatch('tasks/bulk', {
      taskIds: selectedIds.value,
      action,
      payload,
    });
    selectedIds.value = [];
    if (action !== 'delete') refresh();
    if (result?.failed?.length) {
      useAlert(
        t('TASKS.BULK.PARTIAL_SUCCESS', {
          ok: result.ok,
          failed: result.failed.length,
        })
      );
    } else {
      useAlert(t('TASKS.BULK.SUCCESS', { n: result?.ok ?? 0 }));
    }
  } catch (error) {
    useAlert(error?.message || t('TASKS.BULK.ERROR'));
  } finally {
    isBulkBusy.value = false;
  }
};

const handleBulkAssign = assigneeId =>
  runBulk('assign', { user_id: assigneeId });

const handleBulkUrgency = urgency => runBulk('set_urgency', { urgency });

const cancelBulk = () => {
  selectedIds.value = [];
};

const handleSelectView = view => {
  activeViewId.value = view.id;
  const merged = { ...filters.value, ...(view.filters || {}) };
  store.dispatch('tasks/setFilters', merged);
  refresh();
};

const handleCreateView = async name => {
  try {
    await store.dispatch('taskViews/create', {
      name,
      filters: filters.value,
    });
    useAlert(t('TASKS.SAVED_VIEWS.CREATED'));
  } catch (error) {
    useAlert(error?.message || t('TASKS.SAVED_VIEWS.ERROR'));
  }
};

const handleRenameView = async ({ id, name }) => {
  try {
    await store.dispatch('taskViews/update', { id, name });
  } catch (error) {
    useAlert(error?.message || t('TASKS.SAVED_VIEWS.ERROR'));
  }
};

const handleDeleteView = async view => {
  if (!window.confirm(t('TASKS.SAVED_VIEWS.DELETE_CONFIRM'))) return;
  try {
    await store.dispatch('taskViews/delete', view.id);
    if (activeViewId.value === view.id) activeViewId.value = null;
  } catch (error) {
    useAlert(error?.message || t('TASKS.SAVED_VIEWS.ERROR'));
  }
};

const handleSetDefaultView = async view => {
  try {
    await store.dispatch('taskViews/setDefault', view.id);
  } catch (error) {
    useAlert(error?.message || t('TASKS.SAVED_VIEWS.ERROR'));
  }
};

const focusAgentFromWorkload = userId => {
  activeView.value = 'list';
  updateFilters({ assignee_id: userId, scope: 'all' });
};

// --- team chat -------------------------------------------------------------
const openChannel = channel => {
  activeView.value = 'chat';
  store.dispatch('teamChat/setActiveChannel', channel.id);
};

const openCreateChannel = () => {
  editingChannel.value = null;
  showChannelModal.value = true;
};

const openEditChannel = channel => {
  editingChannel.value = channel;
  showChannelModal.value = true;
};

const closeChannelModal = () => {
  showChannelModal.value = false;
  editingChannel.value = null;
};

const handleChannelSubmit = async payload => {
  try {
    if (editingChannel.value) {
      await store.dispatch('teamChat/updateChannel', {
        id: editingChannel.value.id,
        ...payload,
      });
      useAlert(t('TEAM_CHAT.CHANNEL.UPDATE_SUCCESS'));
    } else {
      const channel = await store.dispatch('teamChat/createChannel', payload);
      useAlert(t('TEAM_CHAT.CHANNEL.CREATE_SUCCESS'));
      activeView.value = 'chat';
      if (channel?.id) store.dispatch('teamChat/setActiveChannel', channel.id);
    }
    closeChannelModal();
  } catch (error) {
    const message =
      error?.response?.data?.message ||
      error?.message ||
      t('TEAM_CHAT.CHANNEL.SAVE_ERROR');
    useAlert(message);
  }
};

const handleArchiveChannel = async channel => {
  if (
    !window.confirm(
      t('TEAM_CHAT.CHANNEL.ARCHIVE_CONFIRM', { name: channel.name })
    )
  ) {
    return;
  }
  try {
    await store.dispatch('teamChat/archiveChannel', channel.id);
    useAlert(t('TEAM_CHAT.CHANNEL.ARCHIVE_SUCCESS'));
    if (!chatChannels.value.length) activeView.value = 'list';
  } catch (error) {
    const message =
      error?.response?.data?.message ||
      error?.message ||
      t('TEAM_CHAT.CHANNEL.SAVE_ERROR');
    useAlert(message);
  }
};

const hydrateFromSettings = () => {
  const cached = uiSettings.value?.[settingsKey.value];
  if (!cached || typeof cached !== 'object') return;
  store.dispatch('tasks/setFilters', cached);
};

watch(activeScope, () => {
  hydrateFromSettings();
});

watch(drawerTaskId, async id => {
  if (!id) return;
  const found = tasks.value.find(task => task.id === id);
  if (!found) {
    try {
      await store.dispatch('tasks/fetchItem', id);
    } catch (_error) {
      // Surface only via the empty drawer state — bad ids open nothing.
    }
  }
});

onMounted(async () => {
  store.dispatch('agents/get');
  hydrateFromSettings();
  refresh();
  try {
    await store.dispatch('taskViews/fetch');
  } catch (_error) {
    // Saved views are non-essential — silently skip if the endpoint fails.
  }
  // Team chat channels load eagerly so the sidebar list is populated even
  // before the user opens chat. Lazy-seeds the four defaults server-side.
  store.dispatch('teamChat/fetchChannels').catch(() => {
    // Non-fatal — the chat section just stays empty if this fails.
  });
});
</script>

<template>
  <div class="flex h-full w-full bg-n-background">
    <aside
      class="hidden md:flex flex-col w-56 flex-shrink-0 border-r border-n-weak bg-n-solid-1/40 overflow-y-auto"
    >
      <div class="px-4 pt-5 pb-3 flex flex-col gap-3">
        <span
          class="text-[10px] uppercase tracking-[0.12em] font-medium text-n-slate-10"
        >
          {{ t('TASKS.TABS.MINE') }}
        </span>
      </div>
      <nav class="flex flex-col gap-0.5 px-2">
        <button
          v-for="tab in TABS"
          :key="tab.key"
          type="button"
          class="flex items-center justify-between gap-2 px-3 h-9 rounded-md text-sm transition-colors"
          :class="[
            activeView === 'list' && activeScope === tab.scope
              ? 'bg-n-alpha-2 text-n-slate-12 font-medium'
              : 'text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1',
          ]"
          :data-test-id="`tasks-tab-${tab.key}`"
          @click="
            activeView = 'list';
            setScope(tab.scope);
          "
        >
          <span class="truncate">{{ t(tab.labelKey) }}</span>
          <span
            v-if="tabCounts[tab.key] > 0"
            class="text-[11px] tabular-nums px-1.5 h-4 inline-flex items-center rounded-md bg-n-alpha-1 text-n-slate-10 ring-1 ring-inset ring-n-weak"
          >
            {{ tabCounts[tab.key] }}
          </span>
        </button>
      </nav>

      <template v-if="isAdmin">
        <div class="mt-6 px-4 mb-2">
          <span
            class="text-[10px] uppercase tracking-[0.12em] font-medium text-n-slate-10"
          >
            {{ t('TASKS.VIEWS.TITLE') }}
          </span>
        </div>
        <nav class="flex flex-col gap-0.5 px-2">
          <button
            v-for="view in ADMIN_VIEWS"
            :key="view.key"
            type="button"
            class="flex items-center justify-between gap-2 px-3 h-9 rounded-md text-sm transition-colors"
            :class="[
              activeView === view.key
                ? 'bg-n-alpha-2 text-n-slate-12 font-medium'
                : 'text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1',
            ]"
            :data-test-id="`tasks-view-${view.key}`"
            @click="activeView = view.key"
          >
            <span class="truncate">{{ t(view.labelKey) }}</span>
          </button>
        </nav>
      </template>

      <div class="mt-6 px-4 mb-2">
        <span
          class="text-[10px] uppercase tracking-[0.12em] font-medium text-n-slate-10"
        >
          {{ t('TASKS.QUICK_FILTERS.TITLE') }}
        </span>
      </div>
      <nav class="flex flex-col gap-0.5 px-2">
        <button
          v-for="filter in QUICK_FILTERS"
          :key="filter.key"
          type="button"
          class="flex items-center gap-2 px-3 h-9 rounded-md text-sm transition-colors"
          :class="[
            activeQuickFilter === filter.key
              ? 'bg-n-alpha-2 text-n-slate-12 font-medium'
              : 'text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1',
          ]"
          @click="
            activeView = 'list';
            applyQuickFilter(filter.key);
          "
        >
          <span class="size-4 flex-shrink-0" :class="[filter.icon]" />
          <span class="flex-1 text-left truncate">{{
            t(filter.labelKey)
          }}</span>
          <span
            v-if="filter.key === 'overdue' && overdueCount > 0"
            class="text-[11px] tabular-nums px-1.5 h-4 inline-flex items-center rounded-md bg-n-ruby-3 text-n-ruby-12 ring-1 ring-inset ring-n-ruby-6"
          >
            {{ overdueCount }}
          </span>
        </button>
      </nav>

      <TaskSavedViewsList
        :views="savedViews"
        :active-view-id="activeViewId"
        @select="handleSelectView"
        @create="handleCreateView"
        @delete="handleDeleteView"
        @set-default="handleSetDefaultView"
        @rename="handleRenameView"
      />

      <div class="mt-6 px-4 mb-2 flex items-center justify-between">
        <span
          class="text-[10px] uppercase tracking-[0.12em] font-medium text-n-slate-10"
        >
          {{ t('TEAM_CHAT.SIDEBAR.TITLE') }}
        </span>
        <button
          v-if="isAdmin"
          type="button"
          class="inline-flex items-center justify-center size-5 rounded text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2 cursor-pointer transition-colors"
          :aria-label="t('TEAM_CHAT.SIDEBAR.NEW_CHANNEL')"
          :title="t('TEAM_CHAT.SIDEBAR.NEW_CHANNEL')"
          @click="openCreateChannel"
        >
          <span class="i-lucide-plus size-3.5" />
        </button>
      </div>
      <nav class="flex flex-col gap-0.5 px-2 pb-4">
        <button
          v-for="channel in chatChannels"
          :key="channel.id"
          type="button"
          class="flex items-center gap-2 px-3 h-9 rounded-md text-sm transition-colors group"
          :class="[
            activeView === 'chat' && activeChatChannelId === channel.id
              ? 'bg-n-alpha-2 text-n-slate-12 font-medium'
              : 'text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1',
          ]"
          @click="openChannel(channel)"
        >
          <span class="i-lucide-hash size-4 flex-shrink-0 text-n-slate-10" />
          <span class="flex-1 text-left truncate">{{ channel.name }}</span>
        </button>
        <p
          v-if="!chatChannels.length"
          class="px-3 py-2 text-xs text-n-slate-10 leading-relaxed"
        >
          {{ t('TEAM_CHAT.SIDEBAR.EMPTY') }}
        </p>
      </nav>
    </aside>

    <main class="flex-1 flex flex-col min-w-0">
      <template v-if="activeView === 'list'">
        <TasksHeader
          :total-count="meta.count"
          :group-by="groupBy"
          @create="showCreateModal = true"
          @refresh="refresh"
          @group-by="groupBy = $event"
        />
        <TasksFilters
          :filters="filters"
          @update="updateFilters"
          @clear="clearFilters"
        />

        <TasksSkeleton v-if="uiFlags.isFetching && !tasks.length" />
        <TasksList
          v-else
          :tasks="tasks"
          :group-by="groupBy"
          :is-filtered="isFiltered"
          :selected-ids="selectedIds"
          @toggle="handleToggle"
          @open="openTask"
          @delete="handleDelete"
          @create="showCreateModal = true"
          @reset="clearFilters"
          @selection-change="handleSelectionChange"
        />
      </template>

      <TeamWorkloadDashboard
        v-else-if="activeView === 'team_board' && isAdmin"
        @focus-agent="focusAgentFromWorkload"
      />

      <TasksReports v-else-if="activeView === 'reports' && isAdmin" />

      <TeamChatPanel
        v-else-if="activeView === 'chat'"
        :channel="activeChatChannel"
        @edit-channel="openEditChannel"
        @archive-channel="handleArchiveChannel"
      />
    </main>

    <TaskCreateModal
      v-if="showCreateModal"
      :is-submitting="uiFlags.isCreating"
      @close="showCreateModal = false"
      @create="handleCreate"
    />

    <TaskDetailDrawer
      v-if="currentTask"
      :task="currentTask"
      @close="closeDrawer"
      @deleted="closeDrawer"
    />

    <TasksBulkActionBar
      :selected-ids="selectedIds"
      :is-busy="isBulkBusy"
      @complete="runBulk('complete')"
      @delete="runBulk('delete')"
      @assign="handleBulkAssign"
      @set-urgency="handleBulkUrgency"
      @cancel="cancelBulk"
    />

    <woot-modal v-model:show="showChannelModal" :on-close="closeChannelModal">
      <TeamChatCreateChannelModal
        v-if="showChannelModal"
        :channel="editingChannel"
        @submit="handleChannelSubmit"
        @close="closeChannelModal"
      />
    </woot-modal>
  </div>
</template>
