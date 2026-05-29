import tasksNotifications from '../../tasksNotifications';
import * as taskSound from '../../../../utils/taskNotificationSound';

vi.mock('../../../../utils/taskNotificationSound', () => ({
  playNotificationSound: vi.fn(),
}));

const { playNotificationSound } = taskSound;

const { actions, mutations } = tasksNotifications;

const buildTask = (overrides = {}) => ({
  id: 42,
  display_id: 42,
  account_id: 7,
  title: 'Ship T3',
  urgency: 'urgent',
  assignees: [{ id: 1, name: 'Diego' }],
  ...overrides,
});

const createContext = (overrides = {}) => {
  const state = {
    toasts: [],
    bellQueue: [],
    unreadCount: 0,
    soundEnabled: false,
    permissionGranted: false,
    recentEventIds: [],
    ...overrides.state,
  };
  const commit = vi.fn((type, payload) => {
    const handler = mutations[type];
    if (handler) handler(state, payload);
  });
  const dispatch = vi.fn((type, payload) => {
    if (type === 'pushToast') {
      return actions.pushToast({ commit }, payload);
    }
    return undefined;
  });
  const rootGetters = {
    getCurrentUserID: 1,
    ...overrides.rootGetters,
  };
  return { commit, dispatch, state, rootGetters };
};

describe('tasksNotifications actions', () => {
  beforeEach(() => {
    playNotificationSound.mockReset();
  });

  describe('handleRealtimeEvent', () => {
    it('forwards task.created to the tasks store and skips the toast', () => {
      const ctx = createContext();
      actions.handleRealtimeEvent(ctx, {
        event: 'task.created',
        payload: buildTask(),
      });
      expect(ctx.dispatch).toHaveBeenCalledWith(
        'tasks/upsertFromRealtime',
        expect.objectContaining({ id: 42 }),
        { root: true }
      );
      expect(ctx.state.toasts).toHaveLength(0);
    });

    it('routes task.assigned to a toast for the current user', () => {
      const ctx = createContext();
      actions.handleRealtimeEvent(ctx, {
        event: 'task.assigned',
        payload: {
          ...buildTask(),
          by_user: { id: 9, name: 'Maya' },
          assigned_user: { id: 1, name: 'Diego' },
        },
      });
      expect(ctx.state.toasts).toHaveLength(1);
      expect(ctx.state.toasts[0].type).toBe('task.assigned');
      expect(ctx.state.unreadCount).toBe(1);
    });

    it('skips task.assigned when the recipient is a different user', () => {
      const ctx = createContext();
      actions.handleRealtimeEvent(ctx, {
        event: 'task.assigned',
        payload: {
          ...buildTask(),
          assigned_user: { id: 99, name: 'Someone else' },
        },
      });
      expect(ctx.state.toasts).toHaveLength(0);
    });

    it('routes task.commented only when the user is an assignee and not the commenter', () => {
      const ctx = createContext();
      actions.handleRealtimeEvent(ctx, {
        event: 'task.commented',
        payload: {
          task: buildTask(),
          comment: { id: 5, body: 'thoughts?', user: { id: 9, name: 'Maya' } },
        },
      });
      expect(ctx.state.toasts).toHaveLength(1);
    });

    it('does not toast on task.commented when the current user is the commenter', () => {
      const ctx = createContext();
      actions.handleRealtimeEvent(ctx, {
        event: 'task.commented',
        payload: {
          task: buildTask(),
          comment: { id: 5, body: 'self', user: { id: 1, name: 'Diego' } },
        },
      });
      expect(ctx.state.toasts).toHaveLength(0);
    });

    it('caps simultaneous visible toasts at 3', () => {
      const ctx = createContext();
      [10, 11, 12, 13].forEach(id => {
        actions.handleRealtimeEvent(ctx, {
          event: 'task.overdue',
          payload: buildTask({ id }),
        });
      });
      expect(ctx.state.toasts).toHaveLength(3);
      expect(ctx.state.bellQueue).toHaveLength(1);
    });

    it('drops duplicates that arrive within the dedupe window', () => {
      const ctx = createContext();
      const payload = buildTask({ id: 77 });
      actions.handleRealtimeEvent(ctx, {
        event: 'task.overdue',
        payload,
      });
      actions.handleRealtimeEvent(ctx, {
        event: 'task.overdue',
        payload,
      });
      expect(ctx.state.toasts).toHaveLength(1);
    });

    it('plays the chime when sound is enabled', () => {
      const ctx = createContext({ state: { soundEnabled: true } });
      actions.handleRealtimeEvent(ctx, {
        event: 'task.overdue',
        payload: buildTask({ id: 88 }),
      });
      expect(playNotificationSound).toHaveBeenCalledWith('urgent');
    });

    it('dispatches removeFromRealtime on task.deleted', () => {
      const ctx = createContext();
      actions.handleRealtimeEvent(ctx, {
        event: 'task.deleted',
        payload: { id: 42 },
      });
      expect(ctx.dispatch).toHaveBeenCalledWith(
        'tasks/removeFromRealtime',
        expect.objectContaining({ id: 42 }),
        { root: true }
      );
    });
  });

  describe('pushToast', () => {
    it('adds the toast and increments unread once', () => {
      const ctx = createContext();
      actions.pushToast(ctx, {
        id: 't1',
        type: 'task.overdue',
        title: 'Overdue',
        body: 'body',
        icon: 'i-lucide-alarm-clock',
        taskId: 1,
      });
      expect(ctx.state.toasts).toHaveLength(1);
      expect(ctx.state.unreadCount).toBe(1);
    });

    it('respects the max-3 cap and overflows older toasts to the bell', () => {
      const ctx = createContext({
        state: {
          toasts: ['a', 'b', 'c'].map(id => ({ id, type: 'task.overdue' })),
        },
      });
      actions.pushToast(ctx, { id: 'd', type: 'task.overdue' });
      expect(ctx.state.toasts.map(t => t.id)).toEqual(['b', 'c', 'd']);
      expect(ctx.state.bellQueue[0].id).toBe('a');
    });
  });

  describe('markAllRead + dismissToast', () => {
    it('markAllRead resets the counter and clears bell overflow', () => {
      const ctx = createContext({
        state: {
          unreadCount: 7,
          bellQueue: [{ id: 'x' }],
        },
      });
      actions.markAllRead(ctx);
      expect(ctx.state.unreadCount).toBe(0);
      expect(ctx.state.bellQueue).toEqual([]);
    });

    it('dismissToast removes the toast by id', () => {
      const ctx = createContext({
        state: {
          toasts: [
            { id: 'a', type: 'task.overdue' },
            { id: 'b', type: 'task.overdue' },
          ],
        },
      });
      actions.dismissToast(ctx, 'a');
      expect(ctx.state.toasts.map(t => t.id)).toEqual(['b']);
    });
  });
});
