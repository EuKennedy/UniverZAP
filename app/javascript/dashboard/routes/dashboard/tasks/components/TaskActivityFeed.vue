<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  activities: {
    type: Array,
    default: () => [],
  },
});

const { t } = useI18n();

const ICON_BY_ACTION = {
  created: 'i-lucide-sparkles',
  status_changed: 'i-lucide-shuffle',
  due_date_changed: 'i-lucide-calendar-clock',
  completed: 'i-lucide-check-check',
};

const labelKey = action => {
  switch (action) {
    case 'created':
      return 'TASKS.DETAIL.ACTIVITY.CREATED';
    case 'status_changed':
      return 'TASKS.DETAIL.ACTIVITY.STATUS_CHANGED';
    case 'due_date_changed':
      return 'TASKS.DETAIL.ACTIVITY.DUE_DATE_CHANGED';
    case 'completed':
      return 'TASKS.DETAIL.ACTIVITY.COMPLETED';
    default:
      return 'TASKS.DETAIL.ACTIVITY.STATUS_CHANGED';
  }
};

const dateFormatter = new Intl.DateTimeFormat(undefined, {
  day: '2-digit',
  month: 'short',
  hour: '2-digit',
  minute: '2-digit',
});

const formatTimestamp = ts => {
  if (!ts) return '';
  const ms = typeof ts === 'number' ? ts * 1000 : Date.parse(ts);
  if (Number.isNaN(ms)) return '';
  return dateFormatter.format(new Date(ms));
};

const iconFor = action => ICON_BY_ACTION[action] || 'i-lucide-activity';

const eventText = activity => {
  const user = activity.user?.name || 'Someone';
  const to = activity.payload?.to ?? '';
  return t(labelKey(activity.action), { user, to });
};
</script>

<template>
  <div>
    <ul v-if="activities.length" class="flex flex-col gap-2.5 list-none m-0">
      <li
        v-for="activity in activities"
        :key="activity.id"
        class="flex items-start gap-3"
      >
        <span
          class="size-6 mt-0.5 grid place-content-center rounded-md bg-n-alpha-1 text-n-slate-11 ring-1 ring-n-weak flex-shrink-0"
        >
          <span class="size-3.5" :class="iconFor(activity.action)" />
        </span>
        <div class="flex flex-col min-w-0">
          <p class="text-sm text-n-slate-12">
            {{ eventText(activity) }}
          </p>
          <span class="text-[11px] text-n-slate-10 tabular-nums">
            {{ formatTimestamp(activity.created_at) }}
          </span>
        </div>
      </li>
    </ul>
    <p v-else class="text-sm text-n-slate-10 text-center py-6">
      {{ t('TASKS.DETAIL.ACTIVITY.EMPTY') }}
    </p>
  </div>
</template>
