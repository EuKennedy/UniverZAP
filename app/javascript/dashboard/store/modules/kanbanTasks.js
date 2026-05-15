import types from '../mutation-types';
import FunnelsAPI from '../../api/funnels';
import KanbanTasksAPI from '../../api/kanbanTasks';

export const state = {
  recordsByFunnel: {},
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isMoving: false,
  },
};

const sortByPosition = list =>
  list.slice().sort((a, b) => a.position - b.position);

export const getters = {
  getTasks: _state => funnelId =>
    sortByPosition(_state.recordsByFunnel[Number(funnelId)] || []),
  getTasksByStage: _state => (funnelId, stageId) =>
    sortByPosition(
      (_state.recordsByFunnel[Number(funnelId)] || []).filter(
        t => t.funnel_stage_id === Number(stageId)
      )
    ),
  getTask: _state => id => {
    for (const list of Object.values(_state.recordsByFunnel)) {
      const found = list.find(t => t.id === Number(id));
      if (found) return found;
    }
    return null;
  },
  getUIFlags: _state => _state.uiFlags,
};

export const actions = {
  getByFunnel: async ({ commit }, funnelId) => {
    commit(types.SET_KANBAN_TASK_UI_FLAG, { isFetching: true });
    try {
      const response = await FunnelsAPI.fetchTasks(funnelId);
      commit(types.SET_KANBAN_TASKS, {
        funnelId,
        tasks: response.data.payload || response.data,
      });
    } finally {
      commit(types.SET_KANBAN_TASK_UI_FLAG, { isFetching: false });
    }
  },

  createInFunnel: async ({ commit }, { funnelId, payload }) => {
    commit(types.SET_KANBAN_TASK_UI_FLAG, { isCreating: true });
    try {
      const response = await FunnelsAPI.createTask(funnelId, payload);
      commit(types.ADD_KANBAN_TASK, { funnelId, task: response.data });
      return response.data;
    } finally {
      commit(types.SET_KANBAN_TASK_UI_FLAG, { isCreating: false });
    }
  },

  update: async ({ commit }, { id, ...payload }) => {
    commit(types.SET_KANBAN_TASK_UI_FLAG, { isUpdating: true });
    try {
      const response = await KanbanTasksAPI.update(id, payload);
      commit(types.EDIT_KANBAN_TASK, response.data);
      return response.data;
    } finally {
      commit(types.SET_KANBAN_TASK_UI_FLAG, { isUpdating: false });
    }
  },

  delete: async ({ commit }, { id, funnelId }) => {
    await KanbanTasksAPI.delete(id);
    commit(types.DELETE_KANBAN_TASK, { id, funnelId });
  },

  handleRealtimeUpsert: ({ commit, state: s }, task) => {
    const funnelId = Number(task.funnel_id);
    const list = s.recordsByFunnel[funnelId];
    if (!list) return;
    commit(types.EDIT_KANBAN_TASK, task);
  },

  handleRealtimeDelete: ({ commit }, { id, funnel_id: funnelId }) => {
    commit(types.DELETE_KANBAN_TASK, { id, funnelId });
  },

  move: async (
    { commit, getters: g },
    { id, funnelStageId, position, funnelId }
  ) => {
    const existing = g.getTask(id);
    commit(types.MOVE_KANBAN_TASK, {
      id,
      funnelId: funnelId ?? existing?.funnel_id,
      funnelStageId,
      position,
    });
    commit(types.SET_KANBAN_TASK_UI_FLAG, { isMoving: true });
    try {
      const response = await KanbanTasksAPI.move(id, {
        funnel_stage_id: funnelStageId,
        position,
      });
      commit(types.EDIT_KANBAN_TASK, response.data);
      return response.data;
    } finally {
      commit(types.SET_KANBAN_TASK_UI_FLAG, { isMoving: false });
    }
  },
};

export const mutations = {
  [types.SET_KANBAN_TASK_UI_FLAG](_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },

  [types.SET_KANBAN_TASKS](_state, { funnelId, tasks }) {
    _state.recordsByFunnel = {
      ..._state.recordsByFunnel,
      [Number(funnelId)]: tasks,
    };
  },

  [types.ADD_KANBAN_TASK](_state, { funnelId, task }) {
    const list = _state.recordsByFunnel[Number(funnelId)] || [];
    _state.recordsByFunnel = {
      ..._state.recordsByFunnel,
      [Number(funnelId)]: [...list, task],
    };
  },

  [types.EDIT_KANBAN_TASK](_state, task) {
    const funnelId = Number(task.funnel_id);
    const list = _state.recordsByFunnel[funnelId] || [];
    const idx = list.findIndex(t => t.id === task.id);
    let next;
    if (idx === -1) next = [...list, task];
    else {
      next = list.slice();
      next.splice(idx, 1, task);
    }
    _state.recordsByFunnel = { ..._state.recordsByFunnel, [funnelId]: next };
  },

  [types.DELETE_KANBAN_TASK](_state, { id, funnelId }) {
    const fid = Number(funnelId);
    const list = _state.recordsByFunnel[fid] || [];
    _state.recordsByFunnel = {
      ..._state.recordsByFunnel,
      [fid]: list.filter(t => t.id !== Number(id)),
    };
  },

  [types.MOVE_KANBAN_TASK](_state, { id, funnelId, funnelStageId, position }) {
    const fid = Number(funnelId);
    const list = _state.recordsByFunnel[fid] || [];
    const idx = list.findIndex(t => t.id === Number(id));
    if (idx === -1) return;
    const next = list.slice();
    next[idx] = {
      ...next[idx],
      funnel_stage_id: Number(funnelStageId),
      position: Number(position),
    };
    _state.recordsByFunnel = { ..._state.recordsByFunnel, [fid]: next };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
