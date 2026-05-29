import tasksNotifications from '../../tasksNotifications';

const { mutations } = tasksNotifications;

const buildToast = (id = '1') => ({
  id,
  type: 'task.assigned',
  title: 'New task',
  body: 'body',
  icon: 'i-lucide-user-plus',
  tone: 'teal',
  taskId: 10,
  accountId: 2,
  createdAt: Date.now(),
});

const buildState = (overrides = {}) => ({
  toasts: [],
  bellQueue: [],
  unreadCount: 0,
  soundEnabled: false,
  permissionGranted: false,
  recentEventIds: [],
  ...overrides,
});

describe('tasksNotifications mutations', () => {
  it('ADD_TOAST appends when below the visible cap', () => {
    const state = buildState();
    mutations.ADD_TOAST(state, buildToast('a'));
    expect(state.toasts.map(t => t.id)).toEqual(['a']);
  });

  it('ADD_TOAST overflows into the bellQueue when over max', () => {
    const state = buildState({
      toasts: [buildToast('a'), buildToast('b'), buildToast('c')],
    });
    mutations.ADD_TOAST(state, buildToast('d'));
    expect(state.toasts.map(t => t.id)).toEqual(['b', 'c', 'd']);
    expect(state.bellQueue[0].id).toBe('a');
  });

  it('REMOVE_TOAST drops by id', () => {
    const state = buildState({
      toasts: [buildToast('a'), buildToast('b')],
    });
    mutations.REMOVE_TOAST(state, 'a');
    expect(state.toasts.map(t => t.id)).toEqual(['b']);
  });

  it('INC_UNREAD bumps the counter by amount', () => {
    const state = buildState();
    mutations.INC_UNREAD(state, 1);
    mutations.INC_UNREAD(state, 2);
    expect(state.unreadCount).toBe(3);
  });

  it('INC_UNREAD defaults to +1 when amount is omitted', () => {
    const state = buildState();
    mutations.INC_UNREAD(state);
    expect(state.unreadCount).toBe(1);
  });

  it('CLEAR_UNREAD resets the counter and bell queue', () => {
    const state = buildState({
      unreadCount: 4,
      bellQueue: [buildToast('a')],
    });
    mutations.CLEAR_UNREAD(state);
    expect(state.unreadCount).toBe(0);
    expect(state.bellQueue).toEqual([]);
  });

  it('SET_SOUND_ENABLED toggles to a boolean', () => {
    const state = buildState();
    mutations.SET_SOUND_ENABLED(state, true);
    expect(state.soundEnabled).toBe(true);
    mutations.SET_SOUND_ENABLED(state, 0);
    expect(state.soundEnabled).toBe(false);
  });

  it('ENQUEUE_BELL prepends and caps at 50 entries', () => {
    const state = buildState({
      bellQueue: Array.from({ length: 50 }, (_, i) => buildToast(`old-${i}`)),
    });
    mutations.ENQUEUE_BELL(state, buildToast('new'));
    expect(state.bellQueue).toHaveLength(50);
    expect(state.bellQueue[0].id).toBe('new');
  });

  it('TRACK_EVENT_ID prunes entries older than the dedupe window', () => {
    const ancient = Date.now() - 60_000;
    const state = buildState({
      recentEventIds: [{ signature: 'task.created:9', at: ancient }],
    });
    mutations.TRACK_EVENT_ID(state, 'task.created:42');
    const signatures = state.recentEventIds.map(e => e.signature);
    expect(signatures).toEqual(['task.created:42']);
  });
});
