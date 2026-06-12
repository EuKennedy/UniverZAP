import ChatflowsAPI from '../../api/chatflows';

export const state = {
  records: [],
  // Full graph of the chatflow currently open in the builder.
  active: { chatflow: null, nodes: [], edges: [] },
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isFetchingItem: false,
  },
};

export const getters = {
  getChatflows: _state => _state.records,
  getActiveChatflow: _state => _state.active,
  getUIFlags: _state => _state.uiFlags,
};

export const actions = {
  get: async ({ commit }) => {
    commit('setUIFlag', { isFetching: true });
    try {
      const { data } = await ChatflowsAPI.get();
      commit('setChatflows', data);
    } finally {
      commit('setUIFlag', { isFetching: false });
    }
  },

  show: async ({ commit }, id) => {
    commit('setUIFlag', { isFetchingItem: true });
    try {
      const { data } = await ChatflowsAPI.show(id);
      commit('setActiveChatflow', data);
      return data;
    } finally {
      commit('setUIFlag', { isFetchingItem: false });
    }
  },

  create: async ({ commit }, name) => {
    commit('setUIFlag', { isCreating: true });
    try {
      const { data } = await ChatflowsAPI.create(name);
      commit('upsertChatflow', data);
      return data;
    } finally {
      commit('setUIFlag', { isCreating: false });
    }
  },

  update: async ({ commit }, { id, ...payload }) => {
    commit('setUIFlag', { isUpdating: true });
    try {
      const { data } = await ChatflowsAPI.update(id, payload);
      commit('upsertChatflow', data);
      commit('setActiveChatflow', data);
      return data;
    } finally {
      commit('setUIFlag', { isUpdating: false });
    }
  },

  delete: async ({ commit }, id) => {
    await ChatflowsAPI.delete(id);
    commit('removeChatflow', id);
  },

  activate: async ({ commit }, id) => {
    const { data } = await ChatflowsAPI.activate(id);
    commit('upsertChatflow', data);
    return data;
  },

  archive: async ({ commit }, id) => {
    const { data } = await ChatflowsAPI.archive(id);
    commit('upsertChatflow', data);
    return data;
  },

  test: async ({ commit }, { id, phone }) => {
    const { data } = await ChatflowsAPI.test(id, phone);
    commit('upsertChatflow', data);
    commit('setActiveChatflow', data);
    return data;
  },

  stopTest: async ({ commit }, id) => {
    const { data } = await ChatflowsAPI.stopTest(id);
    commit('upsertChatflow', data);
    commit('setActiveChatflow', data);
    return data;
  },

  // --- graph mutations through the API -----------------------------------

  createNode: async ({ commit }, { chatflowId, node }) => {
    const { data } = await ChatflowsAPI.createNode(chatflowId, node);
    commit('upsertNode', data);
    return data;
  },

  updateNode: async ({ commit }, { chatflowId, nodeId, node }) => {
    const { data } = await ChatflowsAPI.updateNode(chatflowId, nodeId, node);
    commit('upsertNode', data);
    return data;
  },

  deleteNode: async ({ commit }, { chatflowId, nodeId }) => {
    await ChatflowsAPI.deleteNode(chatflowId, nodeId);
    commit('removeNode', nodeId);
  },

  createEdge: async ({ commit }, { chatflowId, edge }) => {
    const { data } = await ChatflowsAPI.createEdge(chatflowId, edge);
    commit('upsertEdge', data);
    return data;
  },

  deleteEdge: async ({ commit }, { chatflowId, edgeId }) => {
    await ChatflowsAPI.deleteEdge(chatflowId, edgeId);
    commit('removeEdge', edgeId);
  },
};

export const mutations = {
  setUIFlag(_state, flag) {
    _state.uiFlags = { ..._state.uiFlags, ...flag };
  },
  setChatflows(_state, records) {
    _state.records = records;
  },
  upsertChatflow(_state, record) {
    const index = _state.records.findIndex(r => r.id === record.id);
    if (index === -1) {
      _state.records.unshift(record);
    } else {
      _state.records.splice(index, 1, { ..._state.records[index], ...record });
    }
  },
  removeChatflow(_state, id) {
    _state.records = _state.records.filter(r => r.id !== id);
  },
  setActiveChatflow(_state, data) {
    _state.active = {
      chatflow: data.id ? data : data.chatflow,
      nodes: data.nodes || [],
      edges: data.edges || [],
    };
  },
  upsertNode(_state, node) {
    const index = _state.active.nodes.findIndex(n => n.id === node.id);
    if (index === -1) {
      _state.active.nodes.push(node);
    } else {
      _state.active.nodes.splice(index, 1, node);
    }
  },
  removeNode(_state, nodeId) {
    _state.active.nodes = _state.active.nodes.filter(n => n.id !== nodeId);
    _state.active.edges = _state.active.edges.filter(
      e => e.source_node_id !== nodeId && e.target_node_id !== nodeId
    );
  },
  upsertEdge(_state, edge) {
    const index = _state.active.edges.findIndex(e => e.id === edge.id);
    if (index === -1) {
      _state.active.edges.push(edge);
    } else {
      _state.active.edges.splice(index, 1, edge);
    }
  },
  removeEdge(_state, edgeId) {
    _state.active.edges = _state.active.edges.filter(e => e.id !== edgeId);
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
