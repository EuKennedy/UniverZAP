import { mount } from '@vue/test-utils';
import TasksList from '../TasksList.vue';

const buildTask = overrides => ({
  id: 1,
  title: 'Task',
  status: 'open',
  urgency: 'urgent',
  due_date: null,
  assignees: [],
  ...overrides,
});

const mountList = props =>
  mount(TasksList, {
    props,
    global: {
      stubs: {
        TaskRow: { template: '<div data-test-id="row" />' },
        TasksEmptyState: {
          template: '<div data-test-id="empty" :data-variant="variant" />',
          props: ['variant'],
        },
      },
    },
  });

describe('TasksList.vue', () => {
  it('renders the empty state when there are no tasks', () => {
    const wrapper = mountList({ tasks: [] });
    expect(wrapper.find('[data-test-id="tasks-list-empty"]').exists()).toBe(
      true
    );
    expect(
      wrapper
        .find('[data-test-id="tasks-list-empty"]')
        .attributes('data-variant')
    ).toBe('default');
  });

  it('switches the empty-state variant when `isFiltered` is true', () => {
    const wrapper = mountList({ tasks: [], isFiltered: true });
    expect(
      wrapper
        .find('[data-test-id="tasks-list-empty"]')
        .attributes('data-variant')
    ).toBe('filtered');
  });

  it('groups tasks by urgency and skips empty buckets', () => {
    const wrapper = mountList({
      tasks: [
        buildTask({ id: 1, urgency: 'urgent' }),
        buildTask({ id: 2, urgency: 'urgent' }),
        buildTask({ id: 3, urgency: 'low' }),
      ],
      groupBy: 'urgency',
    });
    const groups = wrapper.findAll('[data-test-id="tasks-list-group"]');
    expect(groups).toHaveLength(2);
  });

  it('renders a single bucket when groupBy=none', () => {
    const wrapper = mountList({
      tasks: [buildTask({ id: 1 }), buildTask({ id: 2 })],
      groupBy: 'none',
    });
    const groups = wrapper.findAll('[data-test-id="tasks-list-group"]');
    expect(groups).toHaveLength(1);
  });
});
