import axios from 'axios';
import { actions } from '../../conversationLabels';
import * as types from '../../../mutation-types';

const commit = vi.fn();
global.axios = axios;
vi.mock('axios');

describe('#actions', () => {
  describe('#get', () => {
    it('sends correct actions if API is success', async () => {
      axios.get.mockResolvedValue({
        data: { payload: ['customer-success', 'on-hold'] },
      });
      await actions.get({ commit }, 1);
      expect(commit.mock.calls).toEqual([
        [types.default.SET_CONVERSATION_LABELS_UI_FLAG, { isFetching: true }],

        [
          types.default.SET_CONVERSATION_LABELS,
          { id: 1, data: ['customer-success', 'on-hold'] },
        ],
        [types.default.SET_CONVERSATION_LABELS_UI_FLAG, { isFetching: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.get.mockRejectedValue({ message: 'Incorrect header' });
      await actions.get({ commit });
      expect(commit.mock.calls).toEqual([
        [types.default.SET_CONVERSATION_LABELS_UI_FLAG, { isFetching: true }],
        [types.default.SET_CONVERSATION_LABELS_UI_FLAG, { isFetching: false }],
      ]);
    });
  });

  describe('#update, when the label concludes the conversation', () => {
    const rootGetters = {
      'labels/getLabels': [{ title: 'cancelado', closes_conversation: true }],
      getCurrentAccountId: 1,
      'accounts/getAccount': () => ({
        vertical_profile: { schedule_status: 'agendado' },
      }),
    };
    const context = labels => ({
      commit,
      rootGetters,
      getters: { getConversationLabels: () => labels },
    });

    beforeEach(() => commit.mockClear());

    it('takes it out of the queue on the spot', async () => {
      axios.post.mockResolvedValue({ data: { payload: ['agendado'] } });
      await actions.update(context([]), {
        conversationId: 1,
        labels: ['agendado'],
      });
      expect(commit).toHaveBeenCalledWith(
        types.default.CHANGE_CONVERSATION_STATUS,
        { conversationId: 1, status: 'resolved' }
      );
    });

    it('leaves it alone when the label was already there', async () => {
      axios.post.mockResolvedValue({ data: { payload: ['agendado', 'vip'] } });
      await actions.update(context(['agendado']), {
        conversationId: 1,
        labels: ['agendado', 'vip'],
      });
      expect(commit).not.toHaveBeenCalledWith(
        types.default.CHANGE_CONVERSATION_STATUS,
        expect.anything()
      );
    });
  });

  describe('#update', () => {
    it('updates correct actions if API is success', async () => {
      axios.post.mockResolvedValue({
        data: { payload: { conversationId: '1', labels: ['on-hold'] } },
      });
      await actions.update(
        { commit },
        { conversationId: '1', labels: ['on-hold'] }
      );

      expect(commit.mock.calls).toEqual([
        [types.default.SET_CONVERSATION_LABELS_UI_FLAG, { isUpdating: true }],
        [
          types.default.SET_CONVERSATION_LABELS,
          {
            id: '1',
            data: { conversationId: '1', labels: ['on-hold'] },
          },
        ],
        [
          types.default.SET_CONVERSATION_LABELS_UI_FLAG,
          { isUpdating: false, isError: false },
        ],
      ]);
    });

    it('sends correct actions if API is error', async () => {
      axios.post.mockRejectedValue({ message: 'Incorrect header' });
      await actions.update(
        { commit },
        { conversationId: '1', labels: ['on-hold'] }
      );
      expect(commit.mock.calls).toEqual([
        [types.default.SET_CONVERSATION_LABELS_UI_FLAG, { isUpdating: true }],
        [
          types.default.SET_CONVERSATION_LABELS_UI_FLAG,
          { isUpdating: false, isError: true },
        ],
      ]);
    });
  });

  describe('#setBulkConversationLabels', () => {
    it('it send correct mutations', () => {
      actions.setBulkConversationLabels({ commit }, [
        { id: 1, labels: ['customer-support'] },
      ]);
      expect(commit.mock.calls).toEqual([
        [
          types.default.SET_BULK_CONVERSATION_LABELS,
          [{ id: 1, labels: ['customer-support'] }],
        ],
      ]);
    });
  });

  describe('#setBulkConversationLabels', () => {
    it('it send correct mutations', () => {
      actions.setConversationLabel(
        { commit },
        { id: 1, data: ['customer-support'] }
      );
      expect(commit.mock.calls).toEqual([
        [
          types.default.SET_CONVERSATION_LABELS,
          { id: 1, data: ['customer-support'] },
        ],
      ]);
    });
  });
});
