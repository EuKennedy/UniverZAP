import types from '../mutation-types';
import InboxGroupsAPI from '../../api/inboxGroups';

// UniverZAP: the groups of "Canais" (see sidebar/helper/channelGroups.js).
export const state = {
  records: [],
};

export const getters = {
  getInboxGroups: $state => $state.records,
};

export const actions = {
  get: async ({ commit }) => {
    const response = await InboxGroupsAPI.get();
    commit(types.SET_INBOX_GROUPS, response.data.payload);
  },

  create: async ({ commit }, payload) => {
    const response = await InboxGroupsAPI.create(payload);
    commit(types.UPSERT_INBOX_GROUP, response.data);
    return response.data;
  },

  update: async ({ commit }, { id, ...payload }) => {
    const response = await InboxGroupsAPI.update(id, payload);
    commit(types.UPSERT_INBOX_GROUP, response.data);
    return response.data;
  },

  delete: async ({ commit, dispatch }, id) => {
    await InboxGroupsAPI.delete(id);
    commit(types.REMOVE_INBOX_GROUP, id);
    // The database moved this group's inboxes back to their kind.
    await dispatch('inboxes/get', null, { root: true });
  },
};

export const mutations = {
  [types.SET_INBOX_GROUPS]($state, records) {
    $state.records = records;
  },
  [types.UPSERT_INBOX_GROUP]($state, record) {
    const others = $state.records.filter(group => group.id !== record.id);
    $state.records = [...others, record];
  },
  [types.REMOVE_INBOX_GROUP]($state, id) {
    $state.records = $state.records.filter(group => group.id !== id);
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
