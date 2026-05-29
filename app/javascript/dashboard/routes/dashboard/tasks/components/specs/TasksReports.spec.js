import { flushPromises, mount } from '@vue/test-utils';
import { createStore } from 'vuex';

import TasksReports from '../TasksReports.vue';

const fakePayload = {
  created_vs_completed: [
    { date: '2026-05-01', created: 4, completed: 2 },
    { date: '2026-05-02', created: 3, completed: 5 },
  ],
  avg_time_to_complete_by_agent: [
    { user: { id: 1, name: 'Alex' }, avg_hours: 6.4 },
  ],
  overdue_rate_by_agent: [{ user: { id: 1, name: 'Alex' }, rate: 0.12 }],
  open_urgency_distribution: {
    urgent: 1,
    high: 2,
    medium: 3,
    low: 4,
    none: 5,
  },
};

const buildStore = (dispatch = vi.fn().mockResolvedValue(fakePayload)) =>
  createStore({
    actions: {
      'tasks/fetchReports': dispatch,
    },
  });

const mountReports = store =>
  mount(TasksReports, {
    global: {
      plugins: [store],
      mocks: { $t: msg => msg },
      stubs: { BarChart: true },
    },
  });

describe('TasksReports.vue', () => {
  it('loads the reports payload on mount', async () => {
    const dispatch = vi.fn().mockResolvedValue(fakePayload);
    const store = buildStore(dispatch);
    mountReports(store);
    await flushPromises();
    // Vuex action handlers are invoked as (context, payload), so the
    // params we care about live in the second argument.
    const payload = dispatch.mock.calls[0][1];
    expect(payload).toEqual(
      expect.objectContaining({
        from: expect.any(String),
        to: expect.any(String),
      })
    );
  });

  it('renders the four chart cards', async () => {
    const store = buildStore();
    const wrapper = mountReports(store);
    await flushPromises();
    expect(
      wrapper
        .find('[data-test-id="tasks-reports-created-vs-completed"]')
        .exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-test-id="tasks-reports-avg-time"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-test-id="tasks-reports-overdue-rate"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-test-id="tasks-reports-urgency"]').exists()
    ).toBe(true);
  });
});
