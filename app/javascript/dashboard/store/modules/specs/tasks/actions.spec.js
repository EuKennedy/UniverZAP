import axios from 'axios';
import { actions } from '../../tasks';
import types from '../../../mutation-types';
import tasksList from './fixtures';

const commit = vi.fn();
global.axios = axios;
vi.mock('axios');

const baseState = {
  filters: {
    scope: 'mine',
    status: null,
    urgency: null,
    assignee_id: null,
    due_before: null,
    q: null,
  },
};

describe('tasks store actions', () => {
  describe('#fetch', () => {
    it('sets fetching flag, loads records, and accepts plain-array response', async () => {
      axios.get.mockResolvedValue({ data: tasksList });
      await actions.fetch({ commit, state: baseState });
      expect(commit.mock.calls).toEqual([
        [types.SET_TASKS_UI_FLAG, { isFetching: true }],
        [types.SET_TASKS, tasksList],
        [types.SET_TASKS_UI_FLAG, { isFetching: false }],
      ]);
    });

    it('falls back to .payload when wrapped (Chatwoot legacy responses)', async () => {
      axios.get.mockResolvedValue({ data: { payload: tasksList } });
      await actions.fetch({ commit, state: baseState });
      expect(commit).toHaveBeenCalledWith(types.SET_TASKS, tasksList);
    });

    it('still clears the fetching flag on error', async () => {
      axios.get.mockRejectedValue(new Error('boom'));
      await expect(
        actions.fetch({ commit, state: baseState })
      ).rejects.toThrow();
      expect(commit).toHaveBeenLastCalledWith(types.SET_TASKS_UI_FLAG, {
        isFetching: false,
      });
    });
  });

  describe('#create', () => {
    it('posts the payload and stores the new task', async () => {
      axios.post.mockResolvedValue({ data: tasksList[0] });
      await actions.create({ commit }, { title: 'x' });
      expect(commit.mock.calls).toEqual([
        [types.SET_TASKS_UI_FLAG, { isCreating: true }],
        [types.ADD_TASK, tasksList[0]],
        [types.SET_TASKS_UI_FLAG, { isCreating: false }],
      ]);
    });
  });

  describe('#update', () => {
    it('patches and upserts the response', async () => {
      axios.patch.mockResolvedValue({ data: tasksList[0] });
      await actions.update({ commit }, { id: 1, title: 'x' });
      expect(commit.mock.calls).toEqual([
        [types.SET_TASKS_UI_FLAG, { isUpdating: true }],
        [types.UPDATE_TASK, tasksList[0]],
        [types.SET_TASKS_UI_FLAG, { isUpdating: false }],
      ]);
    });
  });

  describe('#delete', () => {
    it('removes the task by id', async () => {
      axios.delete.mockResolvedValue({});
      await actions.delete({ commit }, 1);
      expect(commit.mock.calls).toEqual([
        [types.SET_TASKS_UI_FLAG, { isDeleting: true }],
        [types.REMOVE_TASK, 1],
        [types.SET_TASKS_UI_FLAG, { isDeleting: false }],
      ]);
    });
  });

  describe('#complete', () => {
    it('hits the complete endpoint and upserts', async () => {
      axios.post.mockResolvedValue({ data: tasksList[0] });
      await actions.complete({ commit }, 1);
      expect(commit).toHaveBeenCalledWith(types.UPDATE_TASK, tasksList[0]);
    });
  });

  describe('#assign / #unassign', () => {
    it('forwards user_id to assign and upserts the response', async () => {
      axios.post.mockResolvedValue({ data: tasksList[0] });
      await actions.assign({ commit }, { id: 1, userId: 9 });
      expect(commit).toHaveBeenCalledWith(types.UPDATE_TASK, tasksList[0]);
    });

    it('forwards user_id to unassign and upserts the response', async () => {
      axios.delete.mockResolvedValue({ data: tasksList[0] });
      await actions.unassign({ commit }, { id: 1, userId: 9 });
      expect(commit).toHaveBeenCalledWith(types.UPDATE_TASK, tasksList[0]);
    });
  });

  describe('realtime bridge', () => {
    it('upsertFromRealtime ignores payloads without an id', () => {
      actions.upsertFromRealtime({ commit }, { title: 'no id' });
      expect(commit).not.toHaveBeenCalled();
    });

    it('upsertFromRealtime commits UPDATE_TASK with the payload', () => {
      actions.upsertFromRealtime({ commit }, tasksList[0]);
      expect(commit).toHaveBeenCalledWith(types.UPDATE_TASK, tasksList[0]);
    });

    it('removeFromRealtime accepts both bare id and {id} payload', () => {
      actions.removeFromRealtime({ commit }, { id: 7 });
      expect(commit).toHaveBeenCalledWith(types.REMOVE_TASK, 7);
      commit.mockClear();
      actions.removeFromRealtime({ commit }, 12);
      expect(commit).toHaveBeenCalledWith(types.REMOVE_TASK, 12);
    });
  });

  describe('#setFilters', () => {
    it('forwards the patch to the mutation', () => {
      actions.setFilters({ commit }, { status: 'open' });
      expect(commit).toHaveBeenCalledWith(types.SET_TASKS_FILTERS, {
        status: 'open',
      });
    });
  });
});
