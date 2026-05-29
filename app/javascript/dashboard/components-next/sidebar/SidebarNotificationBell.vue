<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';

const emit = defineEmits(['openNotificationPanel']);

const notificationMetadata = useMapGetter('notifications/getMeta');
const tasksUnread = useMapGetter('tasksNotifications/getUnreadCount');
const route = useRoute();

// Bell badge combines mention/notification unread + task realtime unread
// so a single chip surfaces every actionable signal in the sidebar.
const totalUnread = computed(() => {
  const notifications = notificationMetadata.value?.unreadCount || 0;
  const tasks = tasksUnread.value || 0;
  return notifications + tasks;
});

const unreadCount = computed(() => {
  if (!totalUnread.value) return '';
  return totalUnread.value < 100 ? `${totalUnread.value}` : '99+';
});

function openNotificationPanel() {
  if (route.name !== 'notifications_index') {
    emit('openNotificationPanel');
  }
}
</script>

<template>
  <button
    class="size-8 rounded-lg hover:bg-n-alpha-1 flex-shrink-0 grid place-content-center relative"
    @click="openNotificationPanel"
  >
    <span class="i-lucide-bell size-4" />
    <span
      v-if="unreadCount"
      class="min-h-2 min-w-2 p-0.5 px-1 bg-n-ruby-9 rounded-lg absolute -top-1 -right-1.5 grid place-items-center text-[9px] leading-none text-n-ruby-3"
    >
      {{ unreadCount }}
    </span>
  </button>
</template>
