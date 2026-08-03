<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import AthenasAPI from 'dashboard/api/athenas';

const props = defineProps({
  assistantId: { type: Number, required: true },
});

const { t } = useI18n();

const data = ref(null);
const loading = ref(false);
const days = ref(30);
const PERIODS = [7, 30, 90];

const totals = computed(() => data.value?.totals || {});
const daily = computed(() => data.value?.daily || []);
const replies = computed(() => data.value?.recent_replies || []);
const hasData = computed(() => (totals.value.calls || 0) > 0);

// Automatic review flags. Order matters: it is the severity order the backend
// sorts on, so the worst problem is the first thing read.
const FLAG_ORDER = [
  'preco_inventado',
  'horario_divergente',
  'cliente_insatisfeito',
  'promessa_solta',
  'sem_fonte',
  'baixa_confianca',
];

// Only the first three are wrong answers. The rest are "worth a look", and
// painting those red trains the operator to ignore the colour.
const SEVERE_FLAGS = FLAG_ORDER.slice(0, 3);

const flagLabel = flag => t(`ATHENAS.ANALYTICS.FLAGS.${flag.toUpperCase()}`);

const flagClass = flag =>
  SEVERE_FLAGS.includes(flag)
    ? 'bg-n-ruby-3 text-n-ruby-11 ring-n-ruby-6'
    : 'bg-n-amber-3 text-n-amber-11 ring-n-amber-6';

const flagCounts = computed(() => {
  const counts = data.value?.flags || {};
  return FLAG_ORDER.filter(flag => counts[flag]).map(flag => ({
    flag,
    count: counts[flag],
  }));
});

const confidencePercent = value =>
  value === null || value === undefined ? null : Math.round(value * 100);

const brl = cents =>
  ((cents || 0) / 100).toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  });

const seconds = ms => `${(Math.round(ms || 0) / 1000).toFixed(1)}s`;

const percent = value => (value === null ? '-' : `${value}%`);

// Bars are drawn relative to the busiest day, so the shape of the week is
// readable without pulling in a chart library.
const peak = computed(() =>
  daily.value.reduce((max, d) => Math.max(max, d.calls), 0)
);

const barHeight = calls =>
  peak.value ? `${Math.max(6, Math.round((calls / peak.value) * 100))}%` : '6%';

const shortDate = iso => {
  const [, m, d] = iso.split('-');
  return `${d}/${m}`;
};

const timeAgo = epoch => {
  const mins = Math.round((Date.now() / 1000 - epoch) / 60);
  if (mins < 60) return t('ATHENAS.ANALYTICS.AGO_MIN', { n: mins });
  if (mins < 1440) {
    return t('ATHENAS.ANALYTICS.AGO_HOUR', { n: Math.round(mins / 60) });
  }
  return t('ATHENAS.ANALYTICS.AGO_DAY', { n: Math.round(mins / 1440) });
};

const fetchAnalytics = async () => {
  loading.value = true;
  try {
    const { data: payload } = await AthenasAPI.analytics(props.assistantId, {
      days: days.value,
    });
    data.value = payload;
  } catch {
    data.value = null;
  } finally {
    loading.value = false;
  }
};

watch(days, fetchAnalytics);
onMounted(fetchAnalytics);
</script>

<template>
  <section class="flex flex-col gap-5">
    <header class="flex items-center justify-between gap-4">
      <div class="flex flex-col gap-1">
        <h2 class="text-base font-semibold text-n-slate-12 tracking-tight">
          {{ t('ATHENAS.ANALYTICS.TITLE') }}
        </h2>
        <p class="text-[13px] text-n-slate-11">
          {{ t('ATHENAS.ANALYTICS.SUBTITLE') }}
        </p>
      </div>
      <div class="flex items-center gap-1 p-0.5 rounded-lg bg-n-alpha-2">
        <button
          v-for="period in PERIODS"
          :key="period"
          type="button"
          class="px-2.5 py-1 rounded-md text-[12px] font-medium transition-colors"
          :class="
            days === period
              ? 'bg-n-solid-1 text-n-slate-12 ring-1 ring-n-weak'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="days = period"
        >
          {{ t('ATHENAS.ANALYTICS.DAYS', { n: period }) }}
        </button>
      </div>
    </header>

    <div v-if="loading" class="flex items-center justify-center py-16">
      <span
        class="i-lucide-loader-circle size-6 animate-spin text-n-slate-10"
      />
    </div>

    <div
      v-else-if="!hasData"
      class="flex flex-col items-center gap-2 py-16 text-center rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
    >
      <span
        class="size-12 rounded-2xl bg-gradient-to-br from-n-teal-3 to-transparent ring-1 ring-n-weak grid place-content-center"
      >
        <span class="i-lucide-activity size-6 text-n-teal-11" />
      </span>
      <p class="text-[13px] text-n-slate-11 max-w-xs">
        {{ t('ATHENAS.ANALYTICS.EMPTY') }}
      </p>
    </div>

    <template v-else>
      <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <div
          class="flex flex-col gap-1 p-4 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
        >
          <span class="text-[11px] uppercase tracking-wider text-n-slate-11">
            {{ t('ATHENAS.ANALYTICS.REPLIES') }}
          </span>
          <span class="text-2xl font-semibold text-n-slate-12 tabular-nums">
            {{ totals.replies }}
          </span>
        </div>
        <div
          class="flex flex-col gap-1 p-4 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
        >
          <span class="text-[11px] uppercase tracking-wider text-n-slate-11">
            {{ t('ATHENAS.ANALYTICS.COST') }}
          </span>
          <span class="text-2xl font-semibold text-n-slate-12 tabular-nums">
            {{ brl(totals.cost_cents_brl) }}
          </span>
        </div>
        <div
          class="flex flex-col gap-1 p-4 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
        >
          <span class="text-[11px] uppercase tracking-wider text-n-slate-11">
            {{ t('ATHENAS.ANALYTICS.LATENCY') }}
          </span>
          <span class="text-2xl font-semibold text-n-slate-12 tabular-nums">
            {{ seconds(totals.avg_latency_ms) }}
          </span>
          <span class="text-[11px] text-n-slate-10">
            {{
              t('ATHENAS.ANALYTICS.P95', { v: seconds(totals.p95_latency_ms) })
            }}
          </span>
        </div>
        <div
          class="flex flex-col gap-1 p-4 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
        >
          <span class="text-[11px] uppercase tracking-wider text-n-slate-11">
            {{ t('ATHENAS.ANALYTICS.RELIABILITY') }}
          </span>
          <span
            class="text-2xl font-semibold tabular-nums"
            :class="totals.errors > 0 ? 'text-n-amber-11' : 'text-n-slate-12'"
          >
            {{ percent(totals.success_rate) }}
          </span>
          <span v-if="totals.errors > 0" class="text-[11px] text-n-amber-11">
            {{ t('ATHENAS.ANALYTICS.ERRORS', { n: totals.errors }) }}
          </span>
        </div>
      </div>

      <div
        v-if="flagCounts.length || totals.undelivered"
        class="flex flex-wrap items-center gap-2 p-4 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
      >
        <span class="text-[13px] font-medium text-n-slate-12 mr-1">
          {{ t('ATHENAS.ANALYTICS.REVIEW') }}
        </span>
        <span
          v-for="item in flagCounts"
          :key="item.flag"
          class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-[11px] font-medium ring-1 tabular-nums"
          :class="flagClass(item.flag)"
        >
          {{ flagLabel(item.flag) }}
          <span class="opacity-70">{{ item.count }}</span>
        </span>
        <span
          v-if="totals.undelivered"
          class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-[11px] font-medium ring-1 tabular-nums bg-n-slate-3 text-n-slate-11 ring-n-weak"
        >
          {{ t('ATHENAS.ANALYTICS.UNDELIVERED', { n: totals.undelivered }) }}
        </span>
      </div>

      <div
        class="flex flex-col gap-3 p-4 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
      >
        <span class="text-[13px] font-medium text-n-slate-12">
          {{ t('ATHENAS.ANALYTICS.VOLUME') }}
        </span>
        <div class="flex items-end gap-1 h-24">
          <div
            v-for="day in daily"
            :key="day.date"
            class="flex-1 flex flex-col justify-end h-full group relative"
            :title="`${shortDate(day.date)}: ${day.calls}`"
          >
            <div
              class="w-full rounded-t bg-n-teal-9 group-hover:bg-n-teal-10 transition-colors"
              :style="{ height: barHeight(day.calls) }"
            />
          </div>
        </div>
        <div
          class="flex items-center justify-between text-[11px] text-n-slate-10"
        >
          <span v-if="daily.length">{{ shortDate(daily[0].date) }}</span>
          <span v-if="daily.length > 1">
            {{ shortDate(daily[daily.length - 1].date) }}
          </span>
        </div>
      </div>

      <div class="flex flex-col gap-3">
        <span class="text-[13px] font-medium text-n-slate-12">
          {{ t('ATHENAS.ANALYTICS.RECENT') }}
        </span>
        <p v-if="!replies.length" class="text-[12px] text-n-slate-11">
          {{ t('ATHENAS.ANALYTICS.RECENT_EMPTY') }}
        </p>
        <article
          v-for="reply in replies"
          :key="reply.id"
          class="flex flex-col gap-2 p-4 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
        >
          <p
            v-if="reply.user_message"
            class="text-[12px] text-n-slate-11 leading-relaxed line-clamp-2 pl-3 border-l-2 border-n-weak"
          >
            {{ reply.user_message }}
          </p>
          <p
            class="text-[13px] text-n-slate-12 leading-relaxed whitespace-pre-wrap"
          >
            {{ reply.content }}
          </p>
          <div
            class="flex flex-wrap items-center gap-3 text-[11px] text-n-slate-10 tabular-nums"
          >
            <span
              v-if="reply.auto_flag"
              class="inline-flex items-center px-2 py-0.5 rounded-full font-medium ring-1"
              :class="flagClass(reply.auto_flag)"
            >
              {{ flagLabel(reply.auto_flag) }}
            </span>
            <span>{{ timeAgo(reply.created_at) }}</span>
            <span>{{ seconds(reply.duration_ms) }}</span>
            <span>{{ reply.model }}</span>
            <span v-if="confidencePercent(reply.confidence) !== null">
              {{
                t('ATHENAS.ANALYTICS.CONFIDENCE', {
                  n: confidencePercent(reply.confidence),
                })
              }}
            </span>
          </div>
        </article>
      </div>
    </template>
  </section>
</template>
