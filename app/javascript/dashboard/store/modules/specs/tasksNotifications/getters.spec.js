import tasksNotifications from '../../tasksNotifications';

const { getters } = tasksNotifications;

const buildState = (overrides = {}) => ({
  toasts: [],
  bellQueue: [],
  unreadCount: 0,
  soundEnabled: false,
  permissionGranted: false,
  recentEventIds: [],
  ...overrides,
});

describe('tasksNotifications getters', () => {
  it('getToasts returns the toast list', () => {
    const state = buildState({ toasts: [{ id: 'a' }] });
    expect(getters.getToasts(state)).toEqual([{ id: 'a' }]);
  });

  it('getUnreadCount returns the unread counter', () => {
    expect(getters.getUnreadCount(buildState({ unreadCount: 7 }))).toBe(7);
  });

  it('getBellQueue returns the overflow queue', () => {
    const state = buildState({ bellQueue: [{ id: 'q' }] });
    expect(getters.getBellQueue(state)).toEqual([{ id: 'q' }]);
  });

  it('isSoundEnabled mirrors the state flag', () => {
    expect(getters.isSoundEnabled(buildState({ soundEnabled: true }))).toBe(
      true
    );
    expect(getters.isSoundEnabled(buildState())).toBe(false);
  });

  it('isPermissionGranted mirrors the permission flag', () => {
    expect(
      getters.isPermissionGranted(buildState({ permissionGranted: true }))
    ).toBe(true);
  });
});
