<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';

import TasksHeader from './components/TasksHeader.vue';
import TasksFilters from './components/TasksFilters.vue';
import TasksList from './components/TasksList.vue';
import TasksSkeleton from './components/TasksSkeleton.vue';
import TaskCreateModal from './components/TaskCreateModal.vue';
import TaskDetailDrawer from './components/TaskDetailDrawer.vue';

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();

const tasks = useMapGetter('tasks/getTasks');
const filters = useMapGetter('tasks/getFilters');
const uiFlags = useMapGetter('tasks/getUiFlags');
const mineCount = useMapGetter('tasks/getMineCount');
const overdueCount = useMapGetter('tasks/getOverdueCount');
const meta = useMapGetter('tasks/getMeta');

const showCreateModal = ref(false);
const groupBy = ref('urgency');
const activeQuickFilter = ref(null);

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

const activeScope = computed(() => filters.value.scope || 'mine');

const tabCounts = computed(() => ({
  mine: mineCount.value,
  team: meta.value?.count || 0,
  all: meta.value?.count || 0,
  created_by_me: meta.value?.count || 0,
}));

const refresh = () => {
  store.dispatch('tasks/fetch');
};

const setScope = scope => {
  if (filters.value.scope === scope) return;
  activeQuickFilter.value = null;
  store.dispatch('tasks/setFilters', {
    scope,
    due_before: null,
  });
  refresh();
};

const updateFilters = patch => {
  store.dispatch('tasks/setFilters', patch);
  refresh();
};

const clearFilters = () => {
  activeQuickFilter.value = null;
  store.dispatch('tasks/setFilters', {
    status: null,
    urgency: null,
    assignee_id: null,
    due_before: null,
    q: null,
  });
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

// Lazy-fetch the task when the user lands directly on the deep link before
// the list query has populated `records`.
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

onMounted(() => {
  store.dispatch('agents/get');
  refresh();
});
</script>

<template>
  <div class="flex h-full w-full bg-n-background">
    <aside
      class="hidden md:flex flex-col w-56 flex-shrink-0 border-r border-n-weak bg-n-solid-1/40"
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
            activeScope === tab.scope
              ? 'bg-n-alpha-2 text-n-slate-12 font-medium'
              : 'text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1',
          ]"
          @click="setScope(tab.scope)"
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
          @click="applyQuickFilter(filter.key)"
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
    </aside>

    <main class="flex-1 flex flex-col min-w-0">
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
        @toggle="handleToggle"
        @open="openTask"
        @delete="handleDelete"
        @create="showCreateModal = true"
        @reset="clearFilters"
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
  </div>
</template>
