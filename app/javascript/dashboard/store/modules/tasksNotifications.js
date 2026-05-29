// Vuex module that owns real-time Task notification UX. T3 wiring:
//
//   ActionCable receives a `{ event, data }` envelope from
//   `AccountTasksChannel` and dispatches `handleRealtimeEvent` here.
//   This module:
//     1. Forwards the canonical task payload to T2's `tasks/` store so
//        the list/drawer stays in sync without each consumer wiring up
//        its own channel.
//     2. Decides whether the event deserves a bottom-left toast (e.g.
//        "assigned to you", overdue) and bumps the bell counter.
//     3. Keeps a 30 s dedupe window so cross-tab broadcasts don't
//        produce a swarm of identical toasts.
//
// All side-effects (sound, browser notification) live in actions so
// they stay easy to mock in tests.
import { playNotificationSound } from '../../utils/taskNotificationSound';

const MAX_VISIBLE_TOASTS = 3;
const DEDUPE_WINDOW_MS = 30 * 1000;
const SOUND_STORAGE_KEY = 'univerzap.tasks.notif_sound';

// Events that mutate the list — they hand the payload back to T2's store.
const STORE_SYNC_EVENTS = new Set([
  'task.created',
  'task.updated',
  'task.assigned',
  'task.completed',
  'task.commented',
]);

const REMOVE_EVENTS = new Set(['task.deleted']);

// Events that should always raise a toast.
const ALWAYS_TOAST_EVENTS = new Set([
  'task.assigned',
  'task.due_soon',
  'task.overdue',
]);

const readSoundEnabledFromStorage = () => {
  try {
    return window.localStorage.getItem(SOUND_STORAGE_KEY) === '1';
  } catch (_e) {
    return false;
  }
};

const writeSoundEnabledToStorage = value => {
  try {
    window.localStorage.setItem(SOUND_STORAGE_KEY, value ? '1' : '0');
  } catch (_e) {
    // localStorage may be unavailable (private mode, SSR) — silent fallback.
  }
};

const readBrowserPermission = () => {
  if (typeof window === 'undefined') return false;
  const Notif = window.Notification;
  return Boolean(Notif && Notif.permission === 'granted');
};

const URGENCY_TONE = {
  urgent: 'ruby',
  high: 'amber',
  medium: 'teal',
  low: 'slate',
  none: 'slate',
};

// The broadcaster ships the task as `data` (see Tasks::Broadcaster). Newer
// events may wrap richer envelopes — we keep the helper tolerant of both.
const extractTask = payload => {
  if (!payload) return null;
  if (payload.task) return payload.task;
  if (payload.id || payload.display_id) return payload;
  return null;
};

const extractActor = payload => {
  if (!payload) return null;
  return payload.by_user || payload.actor || payload.assigned_by || null;
};

const titleFor = (event, task, actor, t) => {
  const taskTitle = task?.title || '';
  const actorName = actor?.name || '';
  switch (event) {
    case 'task.assigned':
      return t
        ? t('TASKS.NOTIFICATIONS.ASSIGNED.TITLE')
        : 'Nova tarefa atribuída';
    case 'task.commented':
      return t ? t('TASKS.NOTIFICATIONS.COMMENTED.TITLE') : 'Novo comentário';
    case 'task.completed':
      return t ? t('TASKS.NOTIFICATIONS.COMPLETED.TITLE') : 'Tarefa concluída';
    case 'task.due_soon':
      return t
        ? t('TASKS.NOTIFICATIONS.DUE_SOON.TITLE')
        : 'Tarefa vencendo em breve';
    case 'task.overdue':
      return t ? t('TASKS.NOTIFICATIONS.OVERDUE.TITLE') : 'Tarefa atrasada';
    default:
      return taskTitle || actorName || 'Task event';
  }
};

const bodyFor = (event, task, actor, payload, t) => {
  const taskTitle = task?.title || '';
  const actorName = actor?.name || '';
  switch (event) {
    case 'task.assigned':
      return t
        ? t('TASKS.NOTIFICATIONS.ASSIGNED.BODY', {
            by: actorName,
            title: taskTitle,
            urgency: task?.urgency || '',
          })
        : `${actorName} → ${taskTitle}`;
    case 'task.commented': {
      const commentBy = payload?.comment?.user?.name || actorName;
      return t
        ? t('TASKS.NOTIFICATIONS.COMMENTED.BODY', {
            by: commentBy,
            title: taskTitle,
          })
        : `${commentBy} → ${taskTitle}`;
    }
    case 'task.completed':
      return t
        ? t('TASKS.NOTIFICATIONS.COMPLETED.BODY', {
            by: actorName,
            title: taskTitle,
          })
        : `${actorName} → ${taskTitle}`;
    case 'task.due_soon':
      return t
        ? t('TASKS.NOTIFICATIONS.DUE_SOON.BODY', {
            title: taskTitle,
            when: '',
          })
        : taskTitle;
    case 'task.overdue':
      return t
        ? t('TASKS.NOTIFICATIONS.OVERDUE.BODY', { title: taskTitle })
        : taskTitle;
    default:
      return taskTitle;
  }
};

export const state = {
  toasts: [],
  bellQueue: [],
  unreadCount: 0,
  soundEnabled: readSoundEnabledFromStorage(),
  permissionGranted: readBrowserPermission(),
  recentEventIds: [],
};

export const getters = {
  getToasts: $state => $state.toasts,
  getUnreadCount: $state => $state.unreadCount,
  getBellQueue: $state => $state.bellQueue,
  isSoundEnabled: $state => $state.soundEnabled,
  isPermissionGranted: $state => $state.permissionGranted,
};

const mutations = {
  ADD_TOAST($state, toast) {
    const overflow = $state.toasts.length >= MAX_VISIBLE_TOASTS;
    if (overflow) {
      const [oldest, ...rest] = $state.toasts;
      $state.toasts = [...rest, toast];
      $state.bellQueue = [oldest, ...$state.bellQueue].slice(0, 50);
    } else {
      $state.toasts = [...$state.toasts, toast];
    }
  },
  REMOVE_TOAST($state, id) {
    $state.toasts = $state.toasts.filter(toast => toast.id !== id);
  },
  INC_UNREAD($state, amount = 1) {
    $state.unreadCount += amount;
  },
  CLEAR_UNREAD($state) {
    $state.unreadCount = 0;
    $state.bellQueue = [];
  },
  SET_SOUND_ENABLED($state, value) {
    $state.soundEnabled = Boolean(value);
  },
  SET_PERMISSION_GRANTED($state, value) {
    $state.permissionGranted = Boolean(value);
  },
  ENQUEUE_BELL($state, entry) {
    $state.bellQueue = [entry, ...$state.bellQueue].slice(0, 50);
  },
  TRACK_EVENT_ID($state, signature) {
    const now = Date.now();
    const pruned = $state.recentEventIds.filter(
      ({ at }) => now - at < DEDUPE_WINDOW_MS
    );
    $state.recentEventIds = [...pruned, { signature, at: now }];
  },
};

const buildDedupeSignature = (event, task) => {
  const taskId = task?.id || task?.display_id || 'unknown';
  return `${event}:${taskId}`;
};

const isDuplicateEvent = ($state, signature) => {
  const now = Date.now();
  return $state.recentEventIds.some(
    entry => entry.signature === signature && now - entry.at < DEDUPE_WINDOW_MS
  );
};

const assigneeIdsForTask = task => {
  if (!task?.assignees) return [];
  return task.assignees
    .map(assignee => Number(assignee.id))
    .filter(id => !Number.isNaN(id));
};

const involvesCurrentUser = (task, currentUserId) => {
  if (!currentUserId) return false;
  const uid = Number(currentUserId);
  return assigneeIdsForTask(task).includes(uid);
};

const shouldToastForEvent = (event, task, payload, currentUserId) => {
  if (ALWAYS_TOAST_EVENTS.has(event)) {
    if (event === 'task.assigned') {
      const recipient = payload?.assigned_user?.id || null;
      if (recipient && Number(recipient) !== Number(currentUserId)) {
        // Per-user stream means this should already be filtered, but
        // belt + braces: never toast if it isn't for this user.
        return false;
      }
      return true;
    }
    if (event === 'task.due_soon' || event === 'task.overdue') {
      return involvesCurrentUser(task, currentUserId);
    }
    return true;
  }
  if (event === 'task.commented') {
    const commenterId = payload?.comment?.user?.id;
    if (commenterId && Number(commenterId) === Number(currentUserId)) {
      return false;
    }
    return involvesCurrentUser(task, currentUserId);
  }
  return false;
};

const iconFor = event => {
  switch (event) {
    case 'task.assigned':
      return 'i-lucide-user-plus';
    case 'task.commented':
      return 'i-lucide-message-square';
    case 'task.completed':
      return 'i-lucide-check-circle-2';
    case 'task.due_soon':
      return 'i-lucide-clock';
    case 'task.overdue':
      return 'i-lucide-alarm-clock';
    default:
      return 'i-lucide-list-checks';
  }
};

const buildToast = (event, task, actor, payload, t) => {
  const urgencyTone = URGENCY_TONE[task?.urgency] || URGENCY_TONE.none;
  return {
    id:
      payload?.id ||
      `${event}:${task?.id || 'x'}:${Date.now()}:${Math.random()
        .toString(36)
        .slice(2, 7)}`,
    event,
    type: event,
    title: titleFor(event, task, actor, t),
    body: bodyFor(event, task, actor, payload, t),
    icon: iconFor(event),
    tone: urgencyTone,
    taskId: task?.id || null,
    accountId: task?.account_id || null,
    createdAt: Date.now(),
  };
};

const fireBrowserNotification = (event, toast) => {
  if (typeof window === 'undefined') return;
  const Notif = window.Notification;
  if (!Notif || Notif.permission !== 'granted') return;
  // Only the most actionable events earn an OS-level notification —
  // we don't want to spam users with every comment.
  if (event !== 'task.assigned') return;
  try {
    // eslint-disable-next-line no-new
    new Notif(toast.title, {
      body: toast.body,
      tag: `task-${toast.taskId || 'x'}`,
      silent: true,
    });
  } catch (_e) {
    // Some platforms throw for non-secure contexts — silently ignore.
  }
};

export const actions = {
  handleRealtimeEvent: (
    { commit, dispatch, state: $state, rootGetters },
    { event, payload, t } = {}
  ) => {
    if (!event) return;
    const task = extractTask(payload);

    if (REMOVE_EVENTS.has(event) && task?.id) {
      dispatch('tasks/removeFromRealtime', task, { root: true });
      return;
    }

    if (STORE_SYNC_EVENTS.has(event) && task) {
      dispatch('tasks/upsertFromRealtime', task, { root: true });
    }

    const signature = buildDedupeSignature(event, task);
    if (isDuplicateEvent($state, signature)) return;
    commit('TRACK_EVENT_ID', signature);

    const currentUserId = rootGetters.getCurrentUserID;
    const actor = extractActor(payload);

    if (!shouldToastForEvent(event, task, payload, currentUserId)) return;

    const toast = buildToast(event, task, actor, payload, t);
    dispatch('pushToast', toast);

    if ($state.soundEnabled) {
      try {
        playNotificationSound(task?.urgency);
      } catch (_e) {
        // Audio permission can be revoked mid-session — best-effort only.
      }
    }

    fireBrowserNotification(event, toast);
  },

  pushToast: ({ commit }, toast) => {
    if (!toast) return;
    commit('ADD_TOAST', toast);
    commit('INC_UNREAD', 1);
  },

  dismissToast: ({ commit }, id) => {
    commit('REMOVE_TOAST', id);
  },

  markAllRead: ({ commit }) => {
    commit('CLEAR_UNREAD');
  },

  toggleSound: ({ commit, state: $state }) => {
    const next = !$state.soundEnabled;
    commit('SET_SOUND_ENABLED', next);
    writeSoundEnabledToStorage(next);
    if (next) {
      // Confirm with a single chime so the user immediately validates the
      // permission and hears what to expect.
      try {
        playNotificationSound('medium');
      } catch (_e) {
        // ignored
      }
    }
  },

  setSoundEnabled: ({ commit }, value) => {
    commit('SET_SOUND_ENABLED', value);
    writeSoundEnabledToStorage(value);
  },

  requestBrowserNotificationPermission: async ({ commit }) => {
    if (typeof window === 'undefined' || !window.Notification) return false;
    if (window.Notification.permission === 'granted') {
      commit('SET_PERMISSION_GRANTED', true);
      return true;
    }
    if (window.Notification.permission === 'denied') {
      commit('SET_PERMISSION_GRANTED', false);
      return false;
    }
    const result = await window.Notification.requestPermission();
    const granted = result === 'granted';
    commit('SET_PERMISSION_GRANTED', granted);
    return granted;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
