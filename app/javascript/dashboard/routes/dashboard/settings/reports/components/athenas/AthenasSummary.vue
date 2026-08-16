<script setup>
/**
 * The headline numbers, in the four groups they answer for: what the agents
 * did, how well they did it, what it cost and what it brought in.
 *
 * Stat tiles rather than charts, because each of these IS one number — a
 * one-bar bar chart is the most common way a dashboard misses its own point.
 *
 * A formatação e a regra de cor da variação vivem em ./summaryFormat, porque a
 * faixa no topo de Visão geral mostra os mesmos números e duas cópias disso
 * divergiriam na primeira mudança.
 *
 * Seis delas carregam a variação contra a janela anterior. Número sozinho não
 * responde a única pergunta que o operador faz olhando o mês: 1.240 respostas é
 * muito ou pouco? As outras dez ficam sem seta de propósito, porque com tudo
 * comparado a tela vira um mar de setinhas e nenhuma é lida.
 */
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  formatNumber,
  formatBrl,
  formatBrlFromCents,
  formatPercent,
  formatSeconds,
  formatRoi,
  buildTrend,
  RISING_IS_GOOD,
  RISING_IS_BAD,
  RISING_MEANS_NOTHING,
} from './summaryFormat';

const props = defineProps({
  report: { type: Object, required: true },
});

const { t } = useI18n();

const label = key => t(`ATHENAS_REPORT.SUMMARY.${key}`);

const totals = computed(() => props.report.totals || {});
const quality = computed(() => props.report.quality || {});
const credits = computed(() => props.report.credits || {});
const comparison = computed(() => props.report.comparison || {});

const trend = (key, direction) => buildTrend(comparison.value, key, direction);

// Vazio quando nada foi consumido: dividir um mês silencioso por zero daria um
// infinito, e "o saldo dura para sempre" não é uma informação, é uma piada.
const runway = computed(() => {
  const days = credits.value.days_of_balance_left;
  if (days === null || days === undefined) return null;
  return t('ATHENAS_REPORT.SUMMARY.MONEY.RUNWAY', { n: formatNumber(days) });
});

const groups = computed(() => [
  {
    key: 'OPERATION',
    tiles: [
      {
        key: 'REPLIES',
        value: formatNumber(totals.value.replies),
        trend: trend('replies', RISING_IS_GOOD),
      },
      {
        key: 'CONVERSATIONS',
        value: formatNumber(totals.value.conversations),
        trend: trend('conversations', RISING_IS_GOOD),
      },
      { key: 'P95', value: formatSeconds(totals.value.p95_latency_ms) },
      { key: 'RELIABILITY', value: formatPercent(totals.value.success_rate) },
    ],
  },
  {
    key: 'QUALITY',
    tiles: [
      {
        key: 'FLAGGED',
        value: formatNumber(totals.value.flagged),
        trend: trend('flagged', RISING_IS_BAD),
      },
      { key: 'APPROVAL', value: formatPercent(quality.value.approval_rate) },
      {
        key: 'PENDING',
        value: formatNumber(quality.value.pending_application),
      },
      { key: 'UNDELIVERED', value: formatNumber(totals.value.undelivered) },
    ],
  },
  {
    key: 'MONEY',
    tiles: [
      {
        key: 'SPENT',
        value: formatBrlFromCents(totals.value.cost_cents_brl),
        trend: trend('cost_cents_brl', RISING_MEANS_NOTHING),
      },
      {
        key: 'PER_CONVERSATION',
        value: formatBrl(totals.value.cost_per_conversation_brl),
      },
      { key: 'CACHE', value: formatPercent(totals.value.cache_savings_ratio) },
      {
        key: 'BALANCE',
        value: formatBrlFromCents(credits.value.balance_cents_brl),
        // O saldo sozinho não é uma decisão. "R$ 87,40" vira uma quando vem com
        // quanto tempo isso dura no ritmo do período que está na tela.
        hint: runway.value,
      },
    ],
  },
  {
    key: 'COMMERCIAL',
    tiles: [
      {
        key: 'REVENUE',
        value: formatBrl(totals.value.revenue_brl),
        trend: trend('revenue_brl', RISING_IS_GOOD),
      },
      { key: 'ROI', value: formatRoi(totals.value.roi) },
      {
        key: 'BOOKINGS',
        value: formatNumber(props.report.bookings?.booked),
        trend: trend('bookings', RISING_IS_GOOD),
      },
      {
        key: 'HOT_LEADS',
        value: formatNumber(props.report.leads?.by_band?.hot),
      },
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
          <div class="flex flex-wrap gap-x-2 gap-y-0.5 items-baseline">
            <!-- Proportional figures on purpose: equal-width digits make a
              standalone number look loose at this size. -->
            <span class="text-2xl font-medium text-n-slate-12">
              {{ tile.value }}
            </span>
            <!-- A seta antes do número, porque a direção é o que se lê de
              relance e a porcentagem é o detalhe que vem depois. -->
            <span
              v-if="tile.trend"
              class="flex gap-1 items-center text-[12px] font-medium tabular-nums"
              :class="tile.trend.tone"
              :title="label('COMPARISON')"
            >
              <span aria-hidden="true">{{ tile.trend.arrow }}</span>
              {{ tile.trend.label }}
            </span>
          </div>
          <span v-if="tile.hint" class="text-[12px] text-n-slate-11">
            {{ tile.hint }}
          </span>
        </div>
      </div>
    </section>
  </div>
</template>
