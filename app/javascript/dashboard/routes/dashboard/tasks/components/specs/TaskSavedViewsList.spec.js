import { mount } from '@vue/test-utils';
import TaskSavedViewsList from '../TaskSavedViewsList.vue';

const sampleViews = [
  { id: 1, name: 'Urgent only', shared: false, is_default: false, position: 1 },
  { id: 2, name: 'Team standup', shared: true, is_default: true, position: 0 },
];

const mountList = (views = sampleViews, activeViewId = null) =>
  mount(TaskSavedViewsList, {
    props: { views, activeViewId },
  });

describe('TaskSavedViewsList.vue', () => {
  it('renders one row per view', () => {
    const wrapper = mountList();
    expect(
      wrapper.findAll('[data-test-id^="task-saved-view-"]').length
    ).toBeGreaterThanOrEqual(2);
  });

  it('emits `select` when a view row is clicked', async () => {
    const wrapper = mountList();
    await wrapper.find('[data-test-id="task-saved-view-1"]').trigger('click');
    expect(wrapper.emitted('select')).toBeTruthy();
    expect(wrapper.emitted('select')[0][0].id).toBe(1);
  });

  it('opens the create form and emits `create` on submit', async () => {
    const wrapper = mountList([]);
    await wrapper
      .find('[data-test-id="task-saved-views-create-toggle"]')
      .trigger('click');
    const form = wrapper.find('[data-test-id="task-saved-views-create-form"]');
    expect(form.exists()).toBe(true);
    await form.find('input').setValue('Backlog');
    await form.trigger('submit');
    expect(wrapper.emitted('create')[0][0]).toBe('Backlog');
  });
});
