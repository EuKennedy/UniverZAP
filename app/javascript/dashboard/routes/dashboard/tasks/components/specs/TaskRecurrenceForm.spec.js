import { mount, flushPromises } from '@vue/test-utils';
import TaskRecurrenceForm from '../TaskRecurrenceForm.vue';

const mountForm = (modelValue = {}) =>
  mount(TaskRecurrenceForm, { props: { modelValue } });

describe('TaskRecurrenceForm.vue', () => {
  it('starts collapsed when no rule is configured', () => {
    const wrapper = mountForm();
    expect(
      wrapper.find('[data-test-id="task-recurrence-type-group"]').exists()
    ).toBe(false);
  });

  it('expands when the toggle is checked and defaults to daily', async () => {
    const wrapper = mountForm();
    const toggle = wrapper
      .find('[data-test-id="task-recurrence-toggle"]')
      .find('input');
    await toggle.setValue(true);
    expect(
      wrapper.find('[data-test-id="task-recurrence-type-daily"]').exists()
    ).toBe(true);
  });

  it('emits a weekly rule with the chosen weekday', async () => {
    const wrapper = mountForm({ type: 'weekly', weekdays: [1] });
    await wrapper
      .find('[data-test-id="task-recurrence-type-weekly"]')
      .trigger('click');
    await wrapper
      .find('[data-test-id="task-recurrence-weekday-3"]')
      .trigger('click');
    await flushPromises();
    const events = wrapper.emitted('update:modelValue');
    const last = events[events.length - 1][0];
    expect(last.type).toBe('weekly');
    expect(last.weekdays).toContain(3);
  });

  it('emits a monthly rule with the chosen day', async () => {
    const wrapper = mountForm({ type: 'monthly', day: 15 });
    await wrapper
      .find('[data-test-id="task-recurrence-day-input"]')
      .setValue(20);
    await flushPromises();
    const events = wrapper.emitted('update:modelValue');
    const last = events[events.length - 1][0];
    expect(last.type).toBe('monthly');
    expect(last.day).toBe(20);
  });
});
