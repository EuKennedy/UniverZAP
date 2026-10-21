<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import BroadcastsAPI from 'dashboard/api/broadcasts';
import { usageTone, widthClass } from '../helpers/broadcastList';

// Os quatro números que respondem "os disparos estão funcionando e com
// segurança?" e, embaixo, o uso de hoje de cada conexão contra o teto
// anti-bloqueio — antes de lançar mais uma campanha no mesmo número.
const props = defineProps({
  refreshKey: { type: Number, default: 0 },
});

const emit = defineEmits(['loaded']);

const { t, locale } = useI18n();
const stats = ref(null);

const formatNext = value =>
  value
    ? new Intl.DateTimeFormat(locale.value.replace('_', '-'), {
        weekday: 'short',
        hour: '2-digit',
        minute: '2-digit',
      }).format(new Date(value))
    : '';

const cards = computed(() => {
  const data = stats.value || {};
  const rate = data.reply_rate_30d;
  return [
    {
      key: 'SENT',
      icon: 'i-lucide-send',
      tone: 'bg-n-teal-3 text-n-teal-11',
      value: data.sent_7d ?? '–',
      hint: t('BROADCAST.STATS.SENT_HINT', { count: data.running ?? 0 }),
    },
    {
      key: 'SCHEDULED',
      icon: 'i-lucide-calendar-clock',
      tone: 'bg-n-blue-3 text-n-blue-11',
      value: data.scheduled ?? '–',
      hint: data.next_scheduled_at
        ? t('BROADCAST.STATS.NEXT', {
            date: formatNext(data.next_scheduled_at),
          })
        : t('BROADCAST.STATS.NONE_SCHEDULED'),
    },
    {
      key: 'REPLIES',
      icon: 'i-lucide-message-circle-reply',
      tone: 'bg-n-amber-3 text-n-amber-11',
      value: rate === null || rate === undefined ? '–' : `${rate}%`,
      hint: t('BROADCAST.STATS.REPLIES_HINT'),
    },
    {
      key: 'PROTECTED',
      icon: 'i-lucide-shield-check',
      tone: 'bg-n-alpha-2 text-n-slate-11',
      value: data.skipped_7d ?? '–',
      hint: t(
        'BROADCAST.STATS.OPTED_OUT',
        { count: data.opted_out ?? 0 },
        data.opted_out ?? 0
      ),
    },
  ];
});

const connections = computed(() => stats.value?.connections || []);

const width = (used, cap) => widthClass(cap ? used / cap : 0);

const load = async () => {
  try {
    const { data } = await BroadcastsAPI.stats();
    stats.value = data;
    emit('loaded', data);
  } catch {
    stats.value = null;
  }
};

watch(() => props.refreshKey, load);
onMounted(load);
</script>

<template>
  <div class="flex flex-col gap-3" data-testid="broadcast-stats">
    <div class="grid gap-3 grid-cols-[repeat(auto-fit,minmax(11rem,1fr))]">
      <div
        v-for="card in cards"
        :key="card.key"
        class="flex gap-3 items-center px-4 py-3.5 rounded-xl border border-n-weak bg-n-solid-1"
        :data-testid="`stat-${card.key.toLowerCase()}`"
      >
        <span
          class="flex justify-center items-center rounded-lg size-9 shrink-0"
          :class="card.tone"
        >
          <span class="size-[18px]" :class="card.icon" />
        </span>
        <div class="flex flex-col min-w-0">
          <span
            class="text-[10px] font-semibold tracking-wider uppercase text-n-slate-11"
          >
            {{ t(`BROADCAST.STATS.${card.key}`) }}
          </span>
          <span
            class="text-lg font-bold leading-tight text-n-slate-12"
            data-testid="stat-value"
          >
            {{ card.value }}
          </span>
          <span class="text-[11px] truncate text-n-slate-10">
            {{ card.hint }}
          </span>
        </div>
      </div>
    </div>

    <div
      v-if="connections.length"
      class="flex flex-wrap gap-x-6 gap-y-2 items-center px-4 py-2.5 rounded-xl border border-n-weak bg-n-solid-1"
      data-testid="connection-usage"
    >
      <span
        class="text-[10px] font-semibold tracking-wider uppercase text-n-slate-11"
      >
        {{ t('BROADCAST.STATS.USAGE_TODAY') }}
      </span>
      <div
        v-for="connection in connections"
        :key="connection.inbox_id"
        class="flex gap-2 items-center min-w-0"
      >
        <span class="text-xs truncate text-n-slate-12 max-w-40">
          {{ connection.name }}
        </span>
        <span class="overflow-hidden w-20 h-1.5 rounded-full bg-n-alpha-2">
          <span
            class="block h-full rounded-full"
            :class="[
              usageTone(connection.today, connection.daily_cap),
              width(connection.today, connection.daily_cap),
            ]"
          />
        </span>
        <span class="text-[11px] tabular-nums text-n-slate-11">
          {{
            t('BROADCAST.STATS.USAGE', {
              today: connection.today,
              dailyCap: connection.daily_cap,
              hour: connection.last_hour,
              hourlyCap: connection.hourly_cap,
            })
          }}
        </span>
      </div>
    </div>
  </div>
</template>
