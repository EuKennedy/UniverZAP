<script setup>
/**
 * Os quatro números que respondem "o status está funcionando?" antes de o
 * operador rolar a página: o que saiu, o que vem aí, o que falhou e a taxa de
 * sucesso. Vêm das entregas, que é o que de fato aconteceu em cada número.
 */
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { dateLocale } from '../helpers';

import WhatsAppStatusAPI from 'dashboard/api/whatsappStatus';

const props = defineProps({
  refreshKey: { type: Number, default: 0 },
});

const emit = defineEmits(['loaded']);

const { t, locale } = useI18n();
const label = key => t(`WHATSAPP_PROFILE.STATS.${key}`);

const stats = ref(null);

const formatNext = value =>
  value
    ? new Date(value).toLocaleString(dateLocale(locale), {
        weekday: 'short',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '';

const cards = computed(() => {
  const data = stats.value || {};
  const rate = data.success_rate_30d;
  return [
    {
      key: 'PUBLISHED',
      icon: 'i-lucide-send',
      tone: 'bg-n-teal-3 text-n-teal-11',
      value: data.published_7d ?? '–',
      hint: label('PUBLISHED_HINT'),
    },
    {
      key: 'SCHEDULED',
      icon: 'i-lucide-calendar-clock',
      tone: 'bg-n-blue-3 text-n-blue-11',
      value: data.scheduled ?? '–',
      hint: data.next_scheduled_at
        ? t('WHATSAPP_PROFILE.STATS.NEXT', {
            date: formatNext(data.next_scheduled_at),
          })
        : label('NONE_SCHEDULED'),
    },
    {
      key: 'FAILED',
      icon: 'i-lucide-triangle-alert',
      tone: data.failed_7d
        ? 'bg-n-ruby-3 text-n-ruby-11'
        : 'bg-n-alpha-2 text-n-slate-11',
      value: data.failed_7d ?? '–',
      hint: label('FAILED_HINT'),
    },
    {
      key: 'SUCCESS',
      icon: 'i-lucide-gauge',
      tone: 'bg-n-amber-3 text-n-amber-11',
      value: rate === null || rate === undefined ? '–' : `${rate}%`,
      hint: t('WHATSAPP_PROFILE.STATS.DRAFTS', { count: data.drafts ?? 0 }),
    },
  ];
});

const fetchStats = async () => {
  try {
    const { data } = await WhatsAppStatusAPI.stats();
    stats.value = data;
    emit('loaded', data);
  } catch {
    stats.value = null;
  }
};

watch(() => props.refreshKey, fetchStats);
onMounted(fetchStats);
</script>

<template>
  <div
    class="grid gap-3 grid-cols-[repeat(auto-fit,minmax(11rem,1fr))]"
    data-testid="stats-bar"
  >
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
          {{ label(card.key) }}
        </span>
        <span
          class="text-lg font-bold leading-tight text-n-slate-12"
          data-testid="stat-value"
        >
          {{ card.value }}
        </span>
        <span class="text-[11px] truncate text-n-slate-10">{{
          card.hint
        }}</span>
      </div>
    </div>
  </div>
</template>
