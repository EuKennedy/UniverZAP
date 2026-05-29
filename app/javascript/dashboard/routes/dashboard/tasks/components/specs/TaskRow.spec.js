import { mount } from '@vue/test-utils';
import TaskRow from '../TaskRow.vue';

const baseTask = {
  id: 1,
  title: 'Send the proposal',
  status: 'open',
  urgency: 'urgent',
  due_date: null,
  assignees: [{ id: 7, name: 'Alex', avatar_url: '' }],
};

const mountRow = (overrides = {}) =>
  mount(TaskRow, {
    props: { task: { ...baseTask, ...overrides } },
    global: {
      stubs: {
        Avatar: true,
        TaskUrgencyBadge: true,
        TaskDueDateChip: true,
      },
    },
  });

describe('TaskRow.vue', () => {
  it('renders the task title', () => {
    const wrapper = mountRow();
    expect(wrapper.find('[data-test-id="task-row-title"]').text()).toBe(
      'Send the proposal'
    );
  });

  it('falls back to the "Untitled task" copy when title is blank', () => {
    const wrapper = mountRow({ title: '' });
    expect(wrapper.find('[data-test-id="task-row-title"]').text()).toBe(
      'Untitled task'
    );
  });

  it('applies a strikethrough to completed tasks', () => {
    const wrapper = mountRow({ status: 'done' });
    const title = wrapper.find('[data-test-id="task-row-title"]');
    expect(title.classes().join(' ')).toContain('line-through');
  });

  it('emits `toggle` when the checkbox is clicked and stops propagation', async () => {
    const wrapper = mountRow();
    await wrapper.find('[data-test-id="task-row-toggle"]').trigger('click');
    expect(wrapper.emitted('toggle')).toBeTruthy();
    expect(wrapper.emitted('toggle')[0][0].id).toBe(1);
    // The toggle uses stop modifier — the parent row click MUST NOT fire.
    expect(wrapper.emitted('open')).toBeFalsy();
  });

  it('emits `open` when the row body is clicked', async () => {
    const wrapper = mountRow();
    await wrapper.find('[data-test-id="task-row"]').trigger('click');
    expect(wrapper.emitted('open')).toBeTruthy();
    expect(wrapper.emitted('open')[0][0].id).toBe(1);
  });
});
