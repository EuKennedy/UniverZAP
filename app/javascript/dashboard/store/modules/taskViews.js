import types from '../mutation-types';
import TaskViewsAPI from '../../api/taskViews';

// Saved task-views store. Backend returns the canonical
// `push_event_data` shape (id, name, filters, is_default, shared, ...)
// — same upsert-by-id pattern as the tasks module.

export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
};

export const getters = {
  getViews: $state => $state.records,
  getViewById: $state => id => {
    const numericId = Number(id);
    return $state.records.find(v => v.id === numericId) || null;
  },
  getDefaultView: $state => $state.records.find(v => v.is_default) || null,
  getUiFlags: $state => $state.uiFlags,
};

export const actions = {
  fetch: async ({ commit }) => {
    commit(types.SET_TASK_VIEWS_UI_FLAG, { isFetching: true });
    try {
      const response = await TaskViewsAPI.get();
      const records = response.data?.payload || response.data || [];
      commit(types.SET_TASK_VIEWS, records);
      return records;
    } finally {
      commit(types.SET_TASK_VIEWS_UI_FLAG, { isFetching: false });
    }
  },

  create: async ({ commit }, payload) => {
    commit(types.SET_TASK_VIEWS_UI_FLAG, { isCreating: true });
    try {
      const response = await TaskViewsAPI.create(payload);
      commit(types.ADD_TASK_VIEW, response.data);
      return response.data;
    } finally {
      commit(types.SET_TASK_VIEWS_UI_FLAG, { isCreating: false });
    }
  },

  update: async ({ commit }, { id, ...payload }) => {
    commit(types.SET_TASK_VIEWS_UI_FLAG, { isUpdating: true });
    try {
      const response = await TaskViewsAPI.update(id, payload);
      commit(types.UPDATE_TASK_VIEW, response.data);
      return response.data;
    } finally {
      commit(types.SET_TASK_VIEWS_UI_FLAG, { isUpdating: false });
    }
  },

  delete: async ({ commit }, id) => {
    commit(types.SET_TASK_VIEWS_UI_FLAG, { isDeleting: true });
    try {
      await TaskViewsAPI.delete(id);
      commit(types.REMOVE_TASK_VIEW, id);
    } finally {
      commit(types.SET_TASK_VIEWS_UI_FLAG, { isDeleting: false });
    }
  },

  setDefault: async ({ commit }, id) => {
    const response = await TaskViewsAPI.setDefault(id);
    commit(types.UPDATE_TASK_VIEW, response.data);
    return response.data;
  },
};

export const mutations = {
  [types.SET_TASK_VIEWS_UI_FLAG]($state, data) {
    $state.uiFlags = { ...$state.uiFlags, ...data };
  },

  [types.SET_TASK_VIEWS]($state, records) {
    $state.records = records;
  },

  [types.ADD_TASK_VIEW]($state, view) {
    const idx = $state.records.findIndex(v => v.id === view.id);
    if (idx === -1) {
      $state.records = [...$state.records, view];
    } else {
      const next = $state.records.slice();
      next.splice(idx, 1, view);
      $state.records = next;
    }
  },

  [types.UPDATE_TASK_VIEW]($state, view) {
    const idx = $state.records.findIndex(v => v.id === view.id);
    if (idx === -1) {
      $state.records = [...$state.records, view];
      return;
    }
    const next = $state.records.slice();
    next.splice(idx, 1, view);
    $state.records = next;
  },

  [types.REMOVE_TASK_VIEW]($state, id) {
    const numericId = Number(id);
    $state.records = $state.records.filter(v => v.id !== numericId);
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
