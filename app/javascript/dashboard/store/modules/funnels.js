import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from '../mutation-types';
import FunnelsAPI from '../../api/funnels';

export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
};

const upsertStageInFunnel = (funnel, stage) => {
  if (!funnel) return;
  const stages = funnel.stages || [];
  const idx = stages.findIndex(s => s.id === stage.id);
  if (idx === -1) stages.push(stage);
  else stages.splice(idx, 1, stage);
  stages.sort((a, b) => a.position - b.position);
  funnel.stages = stages;
};

export const getters = {
  getFunnels: _state => _state.records.slice().sort((a, b) => a.position - b.position),
  getFunnel: _state => id =>
    _state.records.find(f => f.id === Number(id)) || null,
  getUIFlags: _state => _state.uiFlags,
};

export const actions = {
  get: async ({ commit }) => {
    commit(types.SET_FUNNEL_UI_FLAG, { isFetching: true });
    try {
      const response = await FunnelsAPI.get();
      commit(types.SET_FUNNELS, response.data.payload || response.data);
    } finally {
      commit(types.SET_FUNNEL_UI_FLAG, { isFetching: false });
    }
  },

  show: async ({ commit }, id) => {
    const response = await FunnelsAPI.show(id);
    commit(types.EDIT_FUNNEL, response.data);
  },

  create: async ({ commit }, payload) => {
    commit(types.SET_FUNNEL_UI_FLAG, { isCreating: true });
    try {
      const response = await FunnelsAPI.create(payload);
      commit(types.ADD_FUNNEL, response.data);
      return response.data;
    } finally {
      commit(types.SET_FUNNEL_UI_FLAG, { isCreating: false });
    }
  },

  update: async ({ commit }, { id, ...payload }) => {
    commit(types.SET_FUNNEL_UI_FLAG, { isUpdating: true });
    try {
      const response = await FunnelsAPI.update(id, payload);
      commit(types.EDIT_FUNNEL, response.data);
      return response.data;
    } finally {
      commit(types.SET_FUNNEL_UI_FLAG, { isUpdating: false });
    }
  },

  delete: async ({ commit }, id) => {
    commit(types.SET_FUNNEL_UI_FLAG, { isDeleting: true });
    try {
      await FunnelsAPI.delete(id);
      commit(types.DELETE_FUNNEL, id);
    } finally {
      commit(types.SET_FUNNEL_UI_FLAG, { isDeleting: false });
    }
  },

  createStage: async ({ commit }, { funnelId, payload }) => {
    const response = await FunnelsAPI.createStage(funnelId, payload);
    commit(types.ADD_FUNNEL_STAGE, { funnelId, stage: response.data });
    return response.data;
  },

  updateStage: async ({ commit }, { funnelId, stageId, payload }) => {
    const response = await FunnelsAPI.updateStage(funnelId, stageId, payload);
    commit(types.EDIT_FUNNEL_STAGE, { funnelId, stage: response.data });
    return response.data;
  },

  deleteStage: async ({ commit }, { funnelId, stageId }) => {
    await FunnelsAPI.deleteStage(funnelId, stageId);
    commit(types.DELETE_FUNNEL_STAGE, { funnelId, stageId });
  },

  reorderStages: async ({ commit }, { funnelId, orderedIds }) => {
    commit(types.REORDER_FUNNEL_STAGES, { funnelId, orderedIds });
    await FunnelsAPI.reorderStages(funnelId, orderedIds);
  },

  handleRealtimeUpsert: ({ commit, state: s }, funnel) => {
    const exists = s.records.some(f => f.id === funnel.id);
    commit(exists ? types.EDIT_FUNNEL : types.ADD_FUNNEL, funnel);
  },

  handleRealtimeDelete: ({ commit }, { id }) => {
    commit(types.DELETE_FUNNEL, id);
  },

  handleStageRealtimeUpsert: ({ commit }, stage) => {
    commit(types.ADD_FUNNEL_STAGE, { funnelId: stage.funnel_id, stage });
  },

  handleStageRealtimeDelete: ({ commit }, { id, funnel_id: funnelId }) => {
    commit(types.DELETE_FUNNEL_STAGE, { funnelId, stageId: id });
  },
};

export const mutations = {
  [types.SET_FUNNEL_UI_FLAG](_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },

  [types.SET_FUNNELS]: MutationHelpers.set,
  [types.ADD_FUNNEL]: MutationHelpers.create,
  [types.EDIT_FUNNEL]: MutationHelpers.update,
  [types.DELETE_FUNNEL]: MutationHelpers.destroy,

  [types.ADD_FUNNEL_STAGE](_state, { funnelId, stage }) {
    const funnel = _state.records.find(f => f.id === Number(funnelId));
    upsertStageInFunnel(funnel, stage);
  },

  [types.EDIT_FUNNEL_STAGE](_state, { funnelId, stage }) {
    const funnel = _state.records.find(f => f.id === Number(funnelId));
    upsertStageInFunnel(funnel, stage);
  },

  [types.DELETE_FUNNEL_STAGE](_state, { funnelId, stageId }) {
    const funnel = _state.records.find(f => f.id === Number(funnelId));
    if (!funnel?.stages) return;
    funnel.stages = funnel.stages.filter(s => s.id !== Number(stageId));
  },

  [types.REORDER_FUNNEL_STAGES](_state, { funnelId, orderedIds }) {
    const funnel = _state.records.find(f => f.id === Number(funnelId));
    if (!funnel?.stages) return;
    const map = new Map(orderedIds.map((id, idx) => [Number(id), idx + 1]));
    funnel.stages = funnel.stages
      .map(s => ({ ...s, position: map.get(s.id) ?? s.position }))
      .sort((a, b) => a.position - b.position);
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
