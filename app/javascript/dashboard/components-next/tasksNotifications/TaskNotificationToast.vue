<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import TaskNotificationToastItem from './TaskNotificationToastItem.vue';

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const { accountId } = useAccount();

const toasts = useMapGetter('tasksNotifications/getToasts');

// Visible stack is capped at 3 — the store already enforces the limit
// but we guard here too so the DOM doesn't go wild if a consumer pushes
// straight into the mutation.
const visibleToasts = computed(() => toasts.value.slice(-3));

const dismissToast = id => {
  store.dispatch('tasksNotifications/dismissToast', id);
};

const openTask = toast => {
  if (!toast.taskId) {
    dismissToast(toast.id);
    return;
  }
  const targetAccountId = toast.accountId || accountId.value;
  router
    .push({
      name: 'tasks',
      params: { accountId: targetAccountId },
      query: { task: String(toast.taskId) },
    })
    .catch(() => {});
  dismissToast(toast.id);
};

const markAsRead = toast => {
  store.dispatch('tasksNotifications/markAllRead');
  dismissToast(toast.id);
};
</script>

<template>
  <Teleport to="body">
    <div
      v-if="visibleToasts.length"
      aria-live="polite"
      :aria-label="t('TASKS.NOTIFICATIONS.ACTIONS.VIEW')"
      class="fixed bottom-4 left-4 z-50 flex flex-col-reverse gap-3 pointer-events-none"
    >
      <TaskNotificationToastItem
        v-for="toast in visibleToasts"
        :key="toast.id"
        :toast="toast"
        :view-label="t('TASKS.NOTIFICATIONS.ACTIONS.VIEW')"
        :mark-read-label="t('TASKS.NOTIFICATIONS.ACTIONS.MARK_READ')"
        :dismiss-label="t('TASKS.NOTIFICATIONS.ACTIONS.DISMISS')"
        class="pointer-events-auto"
        @view="openTask(toast)"
        @mark-read="markAsRead(toast)"
        @dismiss="dismissToast(toast.id)"
      />
    </div>
  </Teleport>
</template>
