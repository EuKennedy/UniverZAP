<script setup>
/**
 * The headline numbers, in the four groups they answer for: what the agents
 * did, how well they did it, what it cost and what it brought in.
 *
 * Stat tiles rather than charts, because each of these IS one number — a
 * one-bar bar chart is the most common way a dashboard misses its own point.
 *
 * Every value that can be absent renders as an em dash and never as zero. "R$
 * 0,00 por agendamento" reads like the agent books for free; "—" reads like
 * nobody booked, which is what it means.
 */
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  report: { type: Object, required: true },
});

const { t } = useI18n();

const label = key => t(`ATHENAS_REPORT.SUMMARY.${key}`);

const number = value =>
  value === null || value === undefined
    ? '—'
    : new Intl.NumberFormat('pt-BR').format(value);

const brlFromCents = cents =>
  cents === null || cents === undefined
    ? '—'
    : new Intl.NumberFormat('pt-BR', {
        style: 'currency',
        currency: 'BRL',
      }).format(cents / 100);

const brl = value =>
  value === null || value === undefined
    ? '—'
    : new Intl.NumberFormat('pt-BR', {
        style: 'currency',
        currency: 'BRL',
      }).format(value);

const percent = value =>
  value === null || value === undefined ? '—' : `${value}%`;

const seconds = ms =>
  ms === null || ms === undefined ? '—' : `${(ms / 1000).toFixed(1)}s`;

const totals = computed(() => props.report.totals || {});
const quality = computed(() => props.report.quality || {});
const credits = computed(() => props.report.credits || {});

const groups = computed(() => [
  {
    key: 'OPERATION',
    tiles: [
      { key: 'REPLIES', value: number(totals.value.replies) },
      { key: 'CONVERSATIONS', value: number(totals.value.conversations) },
      { key: 'P95', value: seconds(totals.value.p95_latency_ms) },
      { key: 'RELIABILITY', value: percent(totals.value.success_rate) },
    ],
  },
  {
    key: 'QUALITY',
    tiles: [
      { key: 'FLAGGED', value: number(totals.value.flagged) },
      { key: 'APPROVAL', value: percent(quality.value.approval_rate) },
      { key: 'PENDING', value: number(quality.value.pending_application) },
      { key: 'UNDELIVERED', value: number(totals.value.undelivered) },
    ],
  },
  {
    key: 'MONEY',
    tiles: [
      { key: 'SPENT', value: brlFromCents(totals.value.cost_cents_brl) },
      {
        key: 'PER_CONVERSATION',
        value: brl(totals.value.cost_per_conversation_brl),
      },
      { key: 'CACHE', value: percent(totals.value.cache_savings_ratio) },
      { key: 'BALANCE', value: brlFromCents(credits.value.balance_cents_brl) },
    ],
  },
  {
    key: 'COMMERCIAL',
    tiles: [
      { key: 'REVENUE', value: brl(totals.value.revenue_brl) },
      // A multiplier, not a percentage: "3,2x o que custou" is the sentence an
      // operator repeats, and a percentage of a cost is a number nobody says.
      {
        key: 'ROI',
        value:
          totals.value.roi === null || totals.value.roi === undefined
            ? '—'
            : `${totals.value.roi.toFixed(2).replace('.', ',')}x`,
      },
      { key: 'BOOKINGS', value: number(props.report.bookings?.booked) },
      { key: 'HOT_LEADS', value: number(props.report.leads?.by_band?.hot) },
    ],
  },
]);
</script>

<template>
  <div class="flex flex-col gap-5">
    <section
      v-for="group in groups"
      :key="group.key"
      class="flex flex-col gap-2"
    >
      <h4
        class="m-0 text-xs font-medium tracking-wide uppercase text-n-slate-11"
      >
        {{ label(`${group.key}.TITLE`) }}
      </h4>
      <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <div
          v-for="tile in group.tiles"
          :key="tile.key"
          class="flex flex-col gap-1 p-3 rounded-lg border border-n-weak bg-n-solid-1"
        >
          <span class="text-[13px] text-n-slate-11">
            {{ label(`${group.key}.${tile.key}`) }}
          </span>
          <!-- Proportional figures on purpose: equal-width digits make a
            standalone number look loose at this size. -->
          <span class="text-2xl font-medium text-n-slate-12">
            {{ tile.value }}
          </span>
        </div>
      </div>
    </section>
  </div>
</template>
