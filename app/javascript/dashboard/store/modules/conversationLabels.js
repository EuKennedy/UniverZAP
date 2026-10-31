import * as types from '../mutation-types';
import ConversationAPI from '../../api/conversations';

const state = {
  records: {},
  uiFlags: {
    isFetching: false,
    isUpdating: false,
    isError: false,
  },
};

export const getters = {
  getUIFlags($state) {
    return $state.uiFlags;
  },
  getConversationLabels: $state => id => {
    return $state.records[Number(id)] || [];
  },
};

// UniverZAP: what a label does to the conversation on the server, mirrored here
// so it moves on the spot (Conversation#handle_closing_label_applied).
const labelEffects = rootGetters => {
  const closing = (rootGetters?.['labels/getLabels'] || [])
    .filter(label => label.closes_conversation)
    .map(label => label.title);
  const profile = rootGetters?.['accounts/getAccount']?.(
    rootGetters?.getCurrentAccountId
  )?.vertical_profile;
  return {
    concluding: [...closing, profile?.schedule_status].filter(Boolean),
    waitingOnContact: profile?.awaiting_customer_statuses || [],
  };
};

export const actions = {
  get: async ({ commit }, conversationId) => {
    commit(types.default.SET_CONVERSATION_LABELS_UI_FLAG, {
      isFetching: true,
    });
    try {
      const response = await ConversationAPI.getLabels(conversationId);
      commit(types.default.SET_CONVERSATION_LABELS, {
        id: conversationId,
        data: response.data.payload,
      });
      commit(types.default.SET_CONVERSATION_LABELS_UI_FLAG, {
        isFetching: false,
      });
    } catch (error) {
      commit(types.default.SET_CONVERSATION_LABELS_UI_FLAG, {
        isFetching: false,
      });
    }
  },
  update: async (
    { commit, getters: localGetters, rootGetters },
    { conversationId, labels }
  ) => {
    commit(types.default.SET_CONVERSATION_LABELS_UI_FLAG, {
      isUpdating: true,
    });
    try {
      const current = localGetters?.getConversationLabels(conversationId) || [];
      const response = await ConversationAPI.updateLabels(
        conversationId,
        labels
      );
      commit(types.default.SET_CONVERSATION_LABELS, {
        id: conversationId,
        data: response.data.payload,
      });
      // Moves on the spot, without waiting for the websocket.
      const { concluding, waitingOnContact } = labelEffects(rootGetters);
      const applied = labels.filter(label => !current.includes(label));
      const conversation = rootGetters?.getConversationById?.(conversationId);
      if (conversation) {
        const handsTurn = applied.some(l => waitingOnContact.includes(l));
        commit(types.default.UPDATE_CONVERSATION, {
          id: conversationId,
          labels: response.data.payload,
          ...(handsTurn && {
            awaiting_reply: false,
            additional_attributes: {
              ...conversation.additional_attributes,
              turn_parked_at: Math.floor(Date.now() / 1000),
            },
          }),
        });
      }
      if (applied.some(label => concluding.includes(label))) {
        commit(types.default.CHANGE_CONVERSATION_STATUS, {
          conversationId,
          status: 'resolved',
        });
      }
      commit(types.default.SET_CONVERSATION_LABELS_UI_FLAG, {
        isUpdating: false,
        isError: false,
      });
    } catch (error) {
      commit(types.default.SET_CONVERSATION_LABELS_UI_FLAG, {
        isUpdating: false,
        isError: true,
      });
    }
  },
  setBulkConversationLabels({ commit }, conversations) {
    commit(types.default.SET_BULK_CONVERSATION_LABELS, conversations);
  },
  setConversationLabel({ commit }, { id, data }) {
    commit(types.default.SET_CONVERSATION_LABELS, { id, data });
  },
};

export const mutations = {
  [types.default.SET_CONVERSATION_LABELS_UI_FLAG]($state, data) {
    $state.uiFlags = {
      ...$state.uiFlags,
      ...data,
    };
  },
  [types.default.SET_CONVERSATION_LABELS]: ($state, { id, data }) => {
    $state.records = { ...$state.records, [id]: data };
  },
  [types.default.SET_BULK_CONVERSATION_LABELS]: ($state, conversations) => {
    const updatedRecords = { ...$state.records };
    conversations.forEach(conversation => {
      updatedRecords[conversation.id] = conversation.labels;
    });

    $state.records = updatedRecords;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
