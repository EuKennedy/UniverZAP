import { mount, flushPromises } from '@vue/test-utils';
import { nextTick } from 'vue';
import TaskNotificationToastItem from '../TaskNotificationToastItem.vue';

const buildToast = (overrides = {}) => ({
  id: 't1',
  type: 'task.assigned',
  title: 'New task assigned',
  body: 'Maya assigned you "Ship T3"',
  icon: 'i-lucide-user-plus',
  tone: 'teal',
  taskId: 42,
  accountId: 7,
  ...overrides,
});

const mountItem = (props = {}) =>
  mount(TaskNotificationToastItem, {
    props: {
      toast: buildToast(),
      viewLabel: 'View task',
      markReadLabel: 'Mark as read',
      dismissLabel: 'Dismiss',
      autoDismissAfterMs: 8000,
      ...props,
    },
  });

describe('TaskNotificationToastItem.vue', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('renders title and body', () => {
    const wrapper = mountItem();
    expect(wrapper.text()).toContain('New task assigned');
    expect(wrapper.text()).toContain('Maya assigned you "Ship T3"');
  });

  it('emits dismiss on X click', async () => {
    const wrapper = mountItem();
    await wrapper
      .find('[data-test-id="task-notification-toast-dismiss"]')
      .trigger('click');
    expect(wrapper.emitted('dismiss')).toBeTruthy();
  });

  it('emits view when the primary action is clicked', async () => {
    const wrapper = mountItem();
    await wrapper
      .find('[data-test-id="task-notification-toast-view"]')
      .trigger('click');
    expect(wrapper.emitted('view')).toBeTruthy();
  });

  it('emits markRead when the secondary action is clicked', async () => {
    const wrapper = mountItem();
    await wrapper
      .find('[data-test-id="task-notification-toast-mark-read"]')
      .trigger('click');
    expect(wrapper.emitted('markRead')).toBeTruthy();
  });

  it('auto-dismisses after the configured timeout', async () => {
    const wrapper = mountItem({ autoDismissAfterMs: 4000 });
    await nextTick();
    vi.advanceTimersByTime(4000);
    await flushPromises();
    expect(wrapper.emitted('dismiss')).toBeTruthy();
  });

  it('pauses auto-dismiss while hovered', async () => {
    const wrapper = mountItem({ autoDismissAfterMs: 4000 });
    await nextTick();
    await wrapper.trigger('mouseenter');
    vi.advanceTimersByTime(10000);
    await flushPromises();
    expect(wrapper.emitted('dismiss')).toBeFalsy();
    await wrapper.trigger('mouseleave');
    vi.advanceTimersByTime(4000);
    await flushPromises();
    expect(wrapper.emitted('dismiss')).toBeTruthy();
  });

  it('uses the urgent tone classes when tone=ruby', () => {
    const wrapper = mountItem({ toast: buildToast({ tone: 'ruby' }) });
    expect(wrapper.html()).toContain('text-n-ruby-11');
  });
});
