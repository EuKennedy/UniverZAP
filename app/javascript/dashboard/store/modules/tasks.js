import types from '../mutation-types';
import TasksAPI from '../../api/tasks';

// Vuex module for the Tasks list. The backend already returns the canonical
// `push_event_data` shape on every endpoint (index, show, mutations) and the
// realtime broadcaster pushes that same shape — so we keep one list (`records`)
// and a single `UPDATE_TASK` mutation that upserts by id.
//
// `upsertFromRealtime` / `removeFromRealtime` are exposed for the T3 ActionCable
// wiring: the channel handler will dispatch them with the broadcast payload.

const URGENCY_ORDER = ['urgent', 'high', 'medium', 'low', 'none'];

const isOverdue = task => {
  if (!task?.due_date) return false;
  if (['done', 'cancelled'].includes(task.status)) return false;
  const due = Number(task.due_date) * 1000;
  return due < Date.now();
};

export const state = {
  records: [],
  currentTask: null,
  uiFlags: {
    isFetching: false,
    isFetchingItem: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
  filters: {
    scope: 'mine',
    status: null,
    urgency: null,
    assignee_id: null,
    due_before: null,
    q: null,
  },
  meta: { count: 0 },
};

export const getters = {
  getTasks: $state => $state.records,
  getTaskById: $state => id => {
    const numericId = Number(id);
    return $state.records.find(t => t.id === numericId) || null;
  },
  getCurrentTask: $state => $state.currentTask,
  getUiFlags: $state => $state.uiFlags,
  getFilters: $state => $state.filters,
  getMeta: $state => $state.meta,
  // Returns an ordered array of `{ urgency, tasks }` groups so the list view
  // can iterate without re-sorting on every render.
  getGroupedByUrgency: $state => {
    const buckets = URGENCY_ORDER.map(urgency => ({ urgency, tasks: [] }));
    const byUrgency = Object.fromEntries(buckets.map(b => [b.urgency, b]));
    $state.records.forEach(task => {
      const bucket = byUrgency[task.urgency] || byUrgency.none;
      bucket.tasks.push(task);
    });
    return buckets.filter(bucket => bucket.tasks.length > 0);
  },
  getMineCount: ($state, _g, _r, rootGetters) => {
    const userId = rootGetters.getCurrentUserID;
    if (!userId) return 0;
    return $state.records.filter(task =>
      (task.assignees || []).some(a => Number(a.id) === Number(userId))
    ).length;
  },
  getOverdueCount: $state => $state.records.filter(isOverdue).length,
};

export const actions = {
  fetch: async ({ commit, state: s }, params = {}) => {
    commit(types.SET_TASKS_UI_FLAG, { isFetching: true });
    try {
      const merged = { ...s.filters, ...params };
      // Strip nullish so the URL stays clean.
      const clean = Object.fromEntries(
        Object.entries(merged).filter(
          ([, value]) => value !== null && value !== '' && value !== undefined
        )
      );
      const response = await TasksAPI.fetch(clean);
      const records = response.data?.payload || response.data || [];
      commit(types.SET_TASKS, records);
      return records;
    } finally {
      commit(types.SET_TASKS_UI_FLAG, { isFetching: false });
    }
  },

  fetchItem: async ({ commit }, id) => {
    commit(types.SET_TASKS_UI_FLAG, { isFetchingItem: true });
    try {
      const response = await TasksAPI.show(id);
      commit(types.SET_CURRENT_TASK, response.data);
      commit(types.UPDATE_TASK, response.data);
      return response.data;
    } finally {
      commit(types.SET_TASKS_UI_FLAG, { isFetchingItem: false });
    }
  },

  create: async ({ commit }, payload) => {
    commit(types.SET_TASKS_UI_FLAG, { isCreating: true });
    try {
      const response = await TasksAPI.create(payload);
      commit(types.ADD_TASK, response.data);
      return response.data;
    } finally {
      commit(types.SET_TASKS_UI_FLAG, { isCreating: false });
    }
  },

  update: async ({ commit }, { id, ...payload }) => {
    commit(types.SET_TASKS_UI_FLAG, { isUpdating: true });
    try {
      const response = await TasksAPI.update(id, payload);
      commit(types.UPDATE_TASK, response.data);
      return response.data;
    } finally {
      commit(types.SET_TASKS_UI_FLAG, { isUpdating: false });
    }
  },

  delete: async ({ commit }, id) => {
    commit(types.SET_TASKS_UI_FLAG, { isDeleting: true });
    try {
      await TasksAPI.delete(id);
      commit(types.REMOVE_TASK, id);
    } finally {
      commit(types.SET_TASKS_UI_FLAG, { isDeleting: false });
    }
  },

  assign: async ({ commit }, { id, userId }) => {
    const response = await TasksAPI.assign(id, userId);
    commit(types.UPDATE_TASK, response.data);
    return response.data;
  },

  unassign: async ({ commit }, { id, userId }) => {
    const response = await TasksAPI.unassign(id, userId);
    commit(types.UPDATE_TASK, response.data);
    return response.data;
  },

  complete: async ({ commit }, id) => {
    const response = await TasksAPI.complete(id);
    commit(types.UPDATE_TASK, response.data);
    return response.data;
  },

  addComment: async (_ctx, { id, body }) => {
    const response = await TasksAPI.addComment(id, body);
    return response.data;
  },

  setFilters: ({ commit }, filters) => {
    commit(types.SET_TASKS_FILTERS, filters);
  },

  // ActionCable bridge (T3 wires the channel handlers here).
  upsertFromRealtime: ({ commit }, task) => {
    if (!task?.id) return;
    commit(types.UPDATE_TASK, task);
  },

  removeFromRealtime: ({ commit }, payload) => {
    const id = typeof payload === 'object' ? payload?.id : payload;
    if (!id) return;
    commit(types.REMOVE_TASK, id);
  },
};

export const mutations = {
  [types.SET_TASKS_UI_FLAG]($state, data) {
    $state.uiFlags = { ...$state.uiFlags, ...data };
  },

  [types.SET_TASKS]($state, records) {
    $state.records = records;
    $state.meta = { count: records.length };
  },

  [types.SET_CURRENT_TASK]($state, task) {
    $state.currentTask = task;
  },

  [types.ADD_TASK]($state, task) {
    const idx = $state.records.findIndex(t => t.id === task.id);
    if (idx === -1) {
      $state.records = [task, ...$state.records];
    } else {
      const next = $state.records.slice();
      next.splice(idx, 1, task);
      $state.records = next;
    }
    $state.meta = { count: $state.records.length };
  },

  [types.UPDATE_TASK]($state, task) {
    const idx = $state.records.findIndex(t => t.id === task.id);
    if (idx === -1) {
      $state.records = [task, ...$state.records];
    } else {
      const next = $state.records.slice();
      next.splice(idx, 1, task);
      $state.records = next;
    }
    if ($state.currentTask?.id === task.id) {
      $state.currentTask = { ...$state.currentTask, ...task };
    }
    $state.meta = { count: $state.records.length };
  },

  [types.REMOVE_TASK]($state, id) {
    const numericId = Number(id);
    $state.records = $state.records.filter(t => t.id !== numericId);
    if ($state.currentTask?.id === numericId) {
      $state.currentTask = null;
    }
    $state.meta = { count: $state.records.length };
  },

  [types.SET_TASKS_FILTERS]($state, filters) {
    $state.filters = { ...$state.filters, ...filters };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
