import TeamChatAPI from '../../api/teamChat';

// Internal team-chat store. Channels are a flat ordered list; messages are
// kept per-channel in `messagesByChannel` so switching channels never
// refetches what's already loaded. Real-time events (AccountTeamChatChannel)
// funnel through `handleRealtimeEvent` and reuse the same upsert paths the
// REST responses do — one code path, no drift between optimistic and pushed
// state.

const MESSAGE_PAGE_SIZE = 40;

export const state = {
  channels: [],
  messagesByChannel: {},
  activeChannelId: null,
  uiFlags: {
    isFetchingChannels: false,
    isFetchingMessages: false,
    isSending: false,
  },
  // channelId => bool. False once a page returns < PAGE_SIZE so the
  // infinite-scroll loader stops hammering the endpoint.
  hasMoreByChannel: {},
};

export const getters = {
  getChannels: _state => _state.channels,
  getActiveChannelId: _state => _state.activeChannelId,
  getActiveChannel: _state =>
    _state.channels.find(c => c.id === _state.activeChannelId) || null,
  getMessages: _state => channelId => _state.messagesByChannel[channelId] || [],
  getUiFlags: _state => _state.uiFlags,
  hasMore: _state => channelId => _state.hasMoreByChannel[channelId] !== false,
};

const sortChannels = list =>
  list.slice().sort((a, b) => a.position - b.position || a.id - b.id);

const upsertById = (list, record) => {
  const idx = list.findIndex(item => item.id === record.id);
  if (idx === -1) return [...list, record];
  const next = list.slice();
  next.splice(idx, 1, record);
  return next;
};

export const actions = {
  fetchChannels: async ({ commit, state: s }) => {
    commit('SET_UI_FLAG', { isFetchingChannels: true });
    try {
      const { data } = await TeamChatAPI.channels();
      commit('SET_CHANNELS', data);
      // Auto-select the first channel on first load so the panel is never
      // empty when the user opens chat.
      if (!s.activeChannelId && data.length) {
        commit('SET_ACTIVE_CHANNEL', data[0].id);
      }
      return data;
    } finally {
      commit('SET_UI_FLAG', { isFetchingChannels: false });
    }
  },

  createChannel: async ({ commit }, payload) => {
    const { data } = await TeamChatAPI.createChannel(payload);
    commit('UPSERT_CHANNEL', data);
    commit('SET_ACTIVE_CHANNEL', data.id);
    return data;
  },

  updateChannel: async ({ commit }, { id, ...payload }) => {
    const { data } = await TeamChatAPI.updateChannel(id, payload);
    commit('UPSERT_CHANNEL', data);
    return data;
  },

  archiveChannel: async ({ commit, state: s }, id) => {
    await TeamChatAPI.archiveChannel(id);
    commit('REMOVE_CHANNEL', id);
    if (s.activeChannelId === id) {
      commit('SET_ACTIVE_CHANNEL', s.channels[0]?.id || null);
    }
  },

  setActiveChannel: ({ commit, dispatch, state: s }, channelId) => {
    commit('SET_ACTIVE_CHANNEL', channelId);
    if (channelId && !s.messagesByChannel[channelId]) {
      dispatch('fetchMessages', channelId);
    }
  },

  fetchMessages: async ({ commit }, channelId) => {
    commit('SET_UI_FLAG', { isFetchingMessages: true });
    try {
      const { data } = await TeamChatAPI.messages(channelId);
      commit('SET_MESSAGES', { channelId, messages: data });
      commit('SET_HAS_MORE', {
        channelId,
        hasMore: data.length >= MESSAGE_PAGE_SIZE,
      });
      return data;
    } finally {
      commit('SET_UI_FLAG', { isFetchingMessages: false });
    }
  },

  loadOlderMessages: async ({ commit, state: s }, channelId) => {
    const loaded = s.messagesByChannel[channelId] || [];
    const beforeId = loaded[0]?.id;
    if (!beforeId) return [];
    const { data } = await TeamChatAPI.messages(channelId, { beforeId });
    commit('PREPEND_MESSAGES', { channelId, messages: data });
    commit('SET_HAS_MORE', {
      channelId,
      hasMore: data.length >= MESSAGE_PAGE_SIZE,
    });
    return data;
  },

  sendMessage: async ({ commit }, { channelId, content }) => {
    commit('SET_UI_FLAG', { isSending: true });
    try {
      const { data } = await TeamChatAPI.sendMessage(channelId, content);
      // The realtime echo also lands; upsert keeps it idempotent.
      commit('UPSERT_MESSAGE', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSending: false });
    }
  },

  editMessage: async ({ commit }, { channelId, messageId, content }) => {
    const { data } = await TeamChatAPI.updateMessage(
      channelId,
      messageId,
      content
    );
    commit('UPSERT_MESSAGE', data);
    return data;
  },

  deleteMessage: async ({ commit }, { channelId, messageId }) => {
    await TeamChatAPI.deleteMessage(channelId, messageId);
    commit('REMOVE_MESSAGE', { channelId, messageId });
  },

  // Single entry point for every websocket payload. Mirrors the event
  // names emitted by TeamChat::Broadcaster.
  handleRealtimeEvent: ({ commit }, { event, payload }) => {
    switch (event) {
      case 'team_chat.channel_created':
      case 'team_chat.channel_updated':
        commit('UPSERT_CHANNEL', payload);
        break;
      case 'team_chat.channel_deleted':
        commit('REMOVE_CHANNEL', payload.id);
        break;
      case 'team_chat.message_created':
      case 'team_chat.message_updated':
        commit('UPSERT_MESSAGE', payload);
        break;
      case 'team_chat.message_deleted':
        commit('REMOVE_MESSAGE', {
          channelId: payload.channel_id,
          messageId: payload.id,
        });
        break;
      default:
        break;
    }
  },
};

export const mutations = {
  SET_UI_FLAG(_state, flags) {
    _state.uiFlags = { ..._state.uiFlags, ...flags };
  },
  SET_CHANNELS(_state, channels) {
    _state.channels = sortChannels(channels);
  },
  UPSERT_CHANNEL(_state, channel) {
    _state.channels = sortChannels(upsertById(_state.channels, channel));
  },
  REMOVE_CHANNEL(_state, id) {
    _state.channels = _state.channels.filter(c => c.id !== id);
  },
  SET_ACTIVE_CHANNEL(_state, id) {
    _state.activeChannelId = id;
  },
  SET_MESSAGES(_state, { channelId, messages }) {
    _state.messagesByChannel = {
      ..._state.messagesByChannel,
      [channelId]: messages,
    };
  },
  PREPEND_MESSAGES(_state, { channelId, messages }) {
    const existing = _state.messagesByChannel[channelId] || [];
    _state.messagesByChannel = {
      ..._state.messagesByChannel,
      [channelId]: [...messages, ...existing],
    };
  },
  UPSERT_MESSAGE(_state, message) {
    const channelId = message.channel_id;
    const existing = _state.messagesByChannel[channelId];
    // Only track messages for channels we've actually opened — otherwise a
    // pushed message for an unopened channel would seed a partial history
    // that infinite-scroll would then mistake for "fully loaded".
    if (!existing) return;
    _state.messagesByChannel = {
      ..._state.messagesByChannel,
      [channelId]: upsertById(existing, message).sort(
        (a, b) => a.created_at - b.created_at || a.id - b.id
      ),
    };
  },
  REMOVE_MESSAGE(_state, { channelId, messageId }) {
    const existing = _state.messagesByChannel[channelId];
    if (!existing) return;
    _state.messagesByChannel = {
      ..._state.messagesByChannel,
      [channelId]: existing.filter(m => m.id !== messageId),
    };
  },
  SET_HAS_MORE(_state, { channelId, hasMore }) {
    _state.hasMoreByChannel = {
      ..._state.hasMoreByChannel,
      [channelId]: hasMore,
    };
  },
};

export default { namespaced: true, state, getters, actions, mutations };
