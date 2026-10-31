<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import GlassNavPanel from 'dashboard/components-next/sidebar/GlassNavPanel.vue';

// UniverZAP: the complementary panel of the conversations screen. Every queue
// and every kind of chat one click away with its live count, so nothing hides
// in the Todos dropdown or in tabs cut off by the list width. Same views and
// same numbers the list already has; it only emits what the tabs emit.
const props = defineProps({
  views: { type: Array, required: true },
  channels: { type: Array, required: true },
  activeKey: { type: String, required: true },
  shortcuts: { type: Array, required: true },
  collapsed: { type: Boolean, default: false },
});

const emit = defineEmits(['selectView', 'selectChannel', 'toggle']);

const { t } = useI18n();

const ICONS = {
  in_attendance: 'i-lucide-messages-square',
  waiting: 'i-lucide-hourglass',
  awaiting_customer: 'i-lucide-reply',
  me: 'i-lucide-user-round',
  unassigned: 'i-lucide-user-round-x',
  scheduled: 'i-lucide-calendar-check',
  resolved: 'i-lucide-circle-check',
  groups: 'i-lucide-users-round',
  status: 'i-lucide-circle-dot',
  team: 'i-lucide-briefcase',
};

const toItem = item => ({
  ...item,
  icon: ICONS[item.key],
  active: item.key === props.activeKey,
  risk: item.key === 'waiting' && item.count > 0,
});

const sections = computed(() => [
  {
    key: 'queues',
    title: t('CHAT_LIST.QUICK_NAV.QUEUES'),
    items: props.views.map(toItem),
  },
  {
    key: 'channels',
    title: t('CHAT_LIST.QUICK_NAV.CHANNELS'),
    items: props.channels.map(toItem),
  },
  {
    key: 'shortcuts',
    title: t('CHAT_LIST.QUICK_NAV.SHORTCUTS'),
    items: props.shortcuts,
    pinned: true,
  },
]);

const onSelect = item => {
  if (props.views.some(view => view.key === item.key)) {
    emit('selectView', item.key);
  } else {
    emit('selectChannel', item.key);
  }
};
</script>

<template>
  <GlassNavPanel
    :title="$t('CHAT_LIST.QUICK_NAV.TITLE')"
    :sections="sections"
    :collapsed="collapsed"
    @select="onSelect"
    @toggle="emit('toggle')"
  />
</template>
