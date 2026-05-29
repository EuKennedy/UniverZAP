import { mount } from '@vue/test-utils';
import TaskCreateModal from '../TaskCreateModal.vue';

const mountModal = (props = {}) =>
  mount(TaskCreateModal, {
    attachTo: document.body,
    props,
    global: {
      stubs: {
        Button: {
          template:
            '<button :type="type" :disabled="disabled"><slot /></button>',
          props: ['type', 'disabled', 'isLoading'],
        },
        TaskAssigneeSelect: true,
      },
    },
  });

describe('TaskCreateModal.vue', () => {
  it('disables submit while the title is blank', () => {
    const wrapper = mountModal();
    const submit = wrapper.find('[data-test-id="task-create-submit"]');
    expect(submit.attributes('disabled')).toBeDefined();
  });

  it('emits `create` with the form payload when submitted', async () => {
    const wrapper = mountModal();
    await wrapper
      .find('[data-test-id="task-create-title"]')
      .setValue('Send proposal');
    await wrapper.find('form').trigger('submit.prevent');

    const created = wrapper.emitted('create');
    expect(created).toBeTruthy();
    expect(created[0][0]).toMatchObject({
      title: 'Send proposal',
      urgency: 'medium',
      notify_assignees: true,
      assignee_ids: [],
    });
  });

  it('does not emit create when the title is blank', async () => {
    const wrapper = mountModal();
    await wrapper.find('form').trigger('submit.prevent');
    expect(wrapper.emitted('create')).toBeFalsy();
  });

  it('emits `close` when the backdrop is clicked', async () => {
    const wrapper = mountModal();
    await wrapper.find('[data-test-id="task-create-modal"]').trigger('click');
    expect(wrapper.emitted('close')).toBeTruthy();
  });
});
