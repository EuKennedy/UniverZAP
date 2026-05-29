import { getters } from '../../tasks';
import tasksList from './fixtures';

describe('tasks store getters', () => {
  it('getTasks returns the records array', () => {
    const state = { records: tasksList };
    expect(getters.getTasks(state)).toEqual(tasksList);
  });

  it('getTaskById returns the matching record or null', () => {
    const state = { records: tasksList };
    expect(getters.getTaskById(state)(2)).toEqual(tasksList[1]);
    expect(getters.getTaskById(state)('2')).toEqual(tasksList[1]);
    expect(getters.getTaskById(state)(999)).toBeNull();
  });

  it('getUiFlags returns the uiFlags slice', () => {
    const state = { uiFlags: { isFetching: true } };
    expect(getters.getUiFlags(state)).toEqual({ isFetching: true });
  });

  it('getFilters returns the filters slice', () => {
    const state = { filters: { scope: 'mine' } };
    expect(getters.getFilters(state)).toEqual({ scope: 'mine' });
  });

  it('getGroupedByUrgency groups in priority order and skips empty buckets', () => {
    const state = { records: tasksList };
    const groups = getters.getGroupedByUrgency(state);
    expect(groups).toHaveLength(3);
    expect(groups[0].urgency).toBe('urgent');
    expect(groups[0].tasks).toHaveLength(1);
    expect(groups[1].urgency).toBe('high');
    expect(groups[2].urgency).toBe('low');
  });

  it('getMineCount counts tasks where the current user is an assignee', () => {
    const state = { records: tasksList };
    const rootGetters = { getCurrentUserID: 7 };
    expect(getters.getMineCount(state, null, null, rootGetters)).toBe(2);
  });

  it('getMineCount returns 0 when there is no current user', () => {
    const state = { records: tasksList };
    expect(getters.getMineCount(state, null, null, {})).toBe(0);
  });

  it('getOverdueCount skips done/cancelled and tasks without due dates', () => {
    const past = Math.floor(Date.now() / 1000) - 3600;
    const future = Math.floor(Date.now() / 1000) + 3600;
    const state = {
      records: [
        { id: 1, status: 'open', due_date: past },
        { id: 2, status: 'open', due_date: future },
        { id: 3, status: 'done', due_date: past },
        { id: 4, status: 'open', due_date: null },
      ],
    };
    expect(getters.getOverdueCount(state)).toBe(1);
  });
});
