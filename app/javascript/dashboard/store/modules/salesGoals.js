import SalesGoalsAPI from '../../api/salesGoals';

export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
  },
};

export const getters = {
  getSalesGoals: _state => _state.records,
  getUIFlags: _state => _state.uiFlags,
};

export const actions = {
  get: async ({ commit }) => {
    commit('setUIFlag', { isFetching: true });
    try {
      const { data } = await SalesGoalsAPI.get();
      commit('setSalesGoals', data);
    } finally {
      commit('setUIFlag', { isFetching: false });
    }
  },

  create: async ({ commit }, payload) => {
    commit('setUIFlag', { isCreating: true });
    try {
      const { data } = await SalesGoalsAPI.create(payload);
      commit('upsertSalesGoal', data);
      return data;
    } finally {
      commit('setUIFlag', { isCreating: false });
    }
  },

  update: async ({ commit }, { id, ...payload }) => {
    commit('setUIFlag', { isUpdating: true });
    try {
      const { data } = await SalesGoalsAPI.update(id, payload);
      commit('upsertSalesGoal', data);
      return data;
    } finally {
      commit('setUIFlag', { isUpdating: false });
    }
  },

  delete: async ({ commit }, id) => {
    await SalesGoalsAPI.delete(id);
    commit('removeSalesGoal', id);
  },
};

export const mutations = {
  setUIFlag(_state, flag) {
    _state.uiFlags = { ..._state.uiFlags, ...flag };
  },
  setSalesGoals(_state, records) {
    _state.records = records;
  },
  upsertSalesGoal(_state, record) {
    const index = _state.records.findIndex(r => r.id === record.id);
    if (index === -1) {
      _state.records.unshift(record);
    } else {
      _state.records.splice(index, 1, { ..._state.records[index], ...record });
    }
  },
  removeSalesGoal(_state, id) {
    _state.records = _state.records.filter(r => r.id !== id);
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
