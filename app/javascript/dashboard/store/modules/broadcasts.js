import BroadcastsAPI from '../../api/broadcasts';

export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isFetchingItem: false,
  },
};

export const getters = {
  getBroadcasts: _state => _state.records,
  getUIFlags: _state => _state.uiFlags,
};

export const actions = {
  get: async ({ commit }) => {
    commit('setUIFlag', { isFetching: true });
    try {
      const { data } = await BroadcastsAPI.get();
      commit('setRecords', data);
    } finally {
      commit('setUIFlag', { isFetching: false });
    }
  },

  show: async ({ commit }, id) => {
    commit('setUIFlag', { isFetchingItem: true });
    try {
      const { data } = await BroadcastsAPI.show(id);
      commit('upsert', data);
      return data;
    } finally {
      commit('setUIFlag', { isFetchingItem: false });
    }
  },

  create: async ({ commit }, payload) => {
    commit('setUIFlag', { isCreating: true });
    try {
      const { data } = await BroadcastsAPI.create(payload);
      commit('upsert', data);
      return data;
    } finally {
      commit('setUIFlag', { isCreating: false });
    }
  },

  update: async ({ commit }, { id, ...payload }) => {
    commit('setUIFlag', { isUpdating: true });
    try {
      const { data } = await BroadcastsAPI.update(id, payload);
      commit('upsert', data);
      return data;
    } finally {
      commit('setUIFlag', { isUpdating: false });
    }
  },

  delete: async ({ commit }, id) => {
    await BroadcastsAPI.delete(id);
    commit('remove', id);
  },

  launch: async ({ commit }, id) => {
    const { data } = await BroadcastsAPI.launch(id);
    commit('upsert', data);
    return data;
  },

  pause: async ({ commit }, id) => {
    const { data } = await BroadcastsAPI.pause(id);
    commit('upsert', data);
    return data;
  },
};

export const mutations = {
  setUIFlag(_state, flag) {
    _state.uiFlags = { ..._state.uiFlags, ...flag };
  },
  setRecords(_state, records) {
    _state.records = records;
  },
  upsert(_state, record) {
    const index = _state.records.findIndex(r => r.id === record.id);
    if (index === -1) {
      _state.records.unshift(record);
    } else {
      _state.records.splice(index, 1, { ..._state.records[index], ...record });
    }
  },
  remove(_state, id) {
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
