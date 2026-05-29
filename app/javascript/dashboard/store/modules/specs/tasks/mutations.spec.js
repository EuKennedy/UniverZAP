import { mutations } from '../../tasks';
import types from '../../../mutation-types';
import tasksList from './fixtures';

const cloneState = () => ({
  records: [],
  currentTask: null,
  uiFlags: {
    isFetching: false,
    isFetchingItem: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
  filters: {
    scope: 'mine',
    status: null,
    urgency: null,
    assignee_id: null,
    due_before: null,
    q: null,
  },
  meta: { count: 0 },
});

describe('tasks store mutations', () => {
  it('SET_TASKS replaces records and recomputes count', () => {
    const state = cloneState();
    mutations[types.SET_TASKS](state, tasksList);
    expect(state.records).toEqual(tasksList);
    expect(state.meta.count).toBe(3);
  });

  it('ADD_TASK prepends a new task', () => {
    const state = cloneState();
    state.records = [tasksList[1]];
    mutations[types.ADD_TASK](state, tasksList[0]);
    expect(state.records[0]).toEqual(tasksList[0]);
    expect(state.meta.count).toBe(2);
  });

  it('ADD_TASK upserts when the id already exists', () => {
    const state = cloneState();
    state.records = [tasksList[0]];
    mutations[types.ADD_TASK](state, { ...tasksList[0], title: 'Renamed' });
    expect(state.records).toHaveLength(1);
    expect(state.records[0].title).toBe('Renamed');
  });

  it('UPDATE_TASK keeps currentTask in sync with the upsert', () => {
    const state = cloneState();
    state.records = [tasksList[0]];
    state.currentTask = { ...tasksList[0] };
    mutations[types.UPDATE_TASK](state, {
      ...tasksList[0],
      status: 'in_progress',
    });
    expect(state.records[0].status).toBe('in_progress');
    expect(state.currentTask.status).toBe('in_progress');
  });

  it('REMOVE_TASK clears the currentTask if it matches', () => {
    const state = cloneState();
    state.records = [tasksList[0]];
    state.currentTask = tasksList[0];
    mutations[types.REMOVE_TASK](state, 1);
    expect(state.records).toEqual([]);
    expect(state.currentTask).toBeNull();
  });

  it('SET_TASKS_FILTERS merges into existing filters', () => {
    const state = cloneState();
    mutations[types.SET_TASKS_FILTERS](state, { status: 'open' });
    expect(state.filters.status).toBe('open');
    expect(state.filters.scope).toBe('mine');
  });

  it('SET_TASKS_UI_FLAG merges flags', () => {
    const state = cloneState();
    mutations[types.SET_TASKS_UI_FLAG](state, { isCreating: true });
    expect(state.uiFlags.isCreating).toBe(true);
    expect(state.uiFlags.isFetching).toBe(false);
  });

  it('SET_CURRENT_TASK stores the task', () => {
    const state = cloneState();
    mutations[types.SET_CURRENT_TASK](state, tasksList[0]);
    expect(state.currentTask).toEqual(tasksList[0]);
  });
});
