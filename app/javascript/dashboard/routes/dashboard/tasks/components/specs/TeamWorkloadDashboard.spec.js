import { flushPromises, mount } from '@vue/test-utils';
import { createStore } from 'vuex';

import TeamWorkloadDashboard from '../TeamWorkloadDashboard.vue';

const fakePayload = {
  totals: { open: 12, overdue: 3, due_today: 5 },
  agents: [
    {
      user: { id: 1, name: 'Alex', avatar_url: '' },
      open_count: 8,
      overdue_count: 2,
      due_today_count: 3,
      completed_this_week: 6,
    },
    {
      user: { id: 2, name: 'Sam', avatar_url: '' },
      open_count: 4,
      overdue_count: 1,
      due_today_count: 2,
      completed_this_week: 4,
    },
  ],
};

const buildStore = (dispatch = vi.fn().mockResolvedValue(fakePayload)) =>
  createStore({
    actions: {
      'tasks/fetchTeamWorkload': dispatch,
    },
  });

const mountDashboard = store =>
  mount(TeamWorkloadDashboard, {
    global: {
      plugins: [store],
      mocks: { $t: msg => msg },
      stubs: { Avatar: true },
    },
  });

describe('TeamWorkloadDashboard.vue', () => {
  it('fetches workload data on mount and renders cards per agent', async () => {
    const dispatch = vi.fn().mockResolvedValue(fakePayload);
    const store = buildStore(dispatch);
    const wrapper = mountDashboard(store);
    await flushPromises();
    expect(
      wrapper.findAll('[data-test-id^="team-workload-card-"]')
    ).toHaveLength(2);
  });

  it('emits `focusAgent` when an agent card is clicked', async () => {
    const store = buildStore();
    const wrapper = mountDashboard(store);
    await flushPromises();
    await wrapper
      .find('[data-test-id="team-workload-card-1"]')
      .trigger('click');
    expect(wrapper.emitted('focusAgent')).toBeTruthy();
    expect(wrapper.emitted('focusAgent')[0][0]).toBe(1);
  });
});
