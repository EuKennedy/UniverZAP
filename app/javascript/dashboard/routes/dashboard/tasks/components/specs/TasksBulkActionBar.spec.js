import { mount } from '@vue/test-utils';
import TasksBulkActionBar from '../TasksBulkActionBar.vue';

const baseStubs = {
  global: {
    stubs: {
      Teleport: { template: '<div><slot /></div>' },
      Button: {
        props: ['label', 'icon', 'disabled'],
        emits: ['click'],
        template:
          '<button type="button" :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
      },
      TaskAssigneeSelect: true,
    },
  },
};

const mountBar = (selectedIds = [1, 2]) =>
  mount(TasksBulkActionBar, {
    props: { selectedIds },
    ...baseStubs,
  });

describe('TasksBulkActionBar.vue', () => {
  it('renders nothing when the selection is empty', () => {
    const wrapper = mountBar([]);
    expect(
      wrapper.find('[data-test-id="tasks-bulk-action-bar"]').exists()
    ).toBe(false);
  });

  it('shows the live selection count', () => {
    const wrapper = mountBar([1, 2, 3]);
    expect(
      wrapper.find('[data-test-id="tasks-bulk-action-count"]').text()
    ).toContain('3');
  });

  it('emits `complete` when the complete button is clicked', async () => {
    const wrapper = mountBar();
    await wrapper.find('[data-test-id="tasks-bulk-complete"]').trigger('click');
    expect(wrapper.emitted('complete')).toBeTruthy();
  });

  it('emits `delete` when the delete button is clicked', async () => {
    const wrapper = mountBar();
    await wrapper.find('[data-test-id="tasks-bulk-delete"]').trigger('click');
    expect(wrapper.emitted('delete')).toBeTruthy();
  });

  it('emits `setUrgency` with the chosen value', async () => {
    const wrapper = mountBar();
    await wrapper
      .find('[data-test-id="tasks-bulk-urgency-toggle"]')
      .trigger('click');
    await wrapper
      .find('[data-test-id="tasks-bulk-urgency-high"]')
      .trigger('click');
    expect(wrapper.emitted('setUrgency')[0][0]).toBe('high');
  });

  it('emits `cancel` when the cancel button is clicked', async () => {
    const wrapper = mountBar();
    await wrapper.find('[data-test-id="tasks-bulk-cancel"]').trigger('click');
    expect(wrapper.emitted('cancel')).toBeTruthy();
  });
});
