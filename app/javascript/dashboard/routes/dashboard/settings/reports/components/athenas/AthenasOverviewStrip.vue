<script setup>
/**
 * Os agentes de IA no topo de Visão geral.
 *
 * Visão geral é a primeira tela que alguém abre em Relatórios, e até aqui ela
 * respondia só pelo time humano. Quem responde a maior parte das mensagens
 * nesta instalação é o Athenas, e essa parte da operação só aparecia depois de
 * três cliques.
 *
 * Seis números e nada além disso. Esta é a faixa de relance: o que ela precisa
 * responder é se o agente está trabalhando e se está se pagando. A aba Agente
 * de IA continua sendo o lugar de investigar, e o link no cabeçalho leva
 * direto para lá.
 *
 * Janela fixa de 30 dias e sem seletor próprio. O resto de Visão geral é ao
 * vivo, e um segundo controle de data numa página de relance convidaria o
 * operador a configurar em vez de olhar.
 */
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { frontendURL } from 'dashboard/helper/URLHelper';
import AthenasAPI from 'dashboard/api/athenas';
import Spinner from 'shared/components/Spinner.vue';
import {
  formatNumber,
  formatBrl,
  formatBrlFromCents,
  formatRoi,
  buildTrend,
  RISING_IS_GOOD,
  RISING_MEANS_NOTHING,
} from './summaryFormat';

const PERIOD_DAYS = 30;

const { t } = useI18n();
const route = useRoute();

const report = ref(null);
const isLoading = ref(true);

// Sem estado de erro e sem bloco vermelho. Isto é uma seção secundária na
// primeira tela da conta: se a requisição falhar, a faixa some e o resto de
// Visão geral segue respondendo. Um alerta aqui pararia a página inteira por
// causa de um módulo que nem todo mundo usa.
onMounted(async () => {
  try {
    const { data } = await AthenasAPI.accountReport({ days: PERIOD_DAYS });
    report.value = data;
  } catch (error) {
    report.value = null;
  } finally {
    isLoading.value = false;
  }
});

// Conta sem nenhum agente não ganha uma parede de R$ 0,00 na tela de abertura:
// isso lê como produto quebrado, não como produto não usado.
const hasAgents = computed(() => (report.value?.agents || []).length > 0);

const reportUrl = computed(() =>
  frontendURL(`accounts/${route.params.accountId}/reports/athenas`)
);

const label = key => t(`ATHENAS_REPORT.OVERVIEW.${key}`);

const metrics = computed(() => {
  const totals = report.value?.totals || {};
  const comparison = report.value?.comparison || {};
  const trend = (key, direction) => buildTrend(comparison, key, direction);

  return [
    {
      key: 'REPLIES',
      value: formatNumber(totals.replies),
      trend: trend('replies', RISING_IS_GOOD),
    },
    {
      key: 'CONVERSATIONS',
      value: formatNumber(totals.conversations),
      trend: trend('conversations', RISING_IS_GOOD),
    },
    {
      key: 'BOOKINGS',
      value: formatNumber(report.value?.bookings?.booked),
      trend: trend('bookings', RISING_IS_GOOD),
    },
    {
      key: 'REVENUE',
      value: formatBrl(totals.revenue_brl),
      trend: trend('revenue_brl', RISING_IS_GOOD),
    },
    {
      key: 'SPENT',
      value: formatBrlFromCents(totals.cost_cents_brl),
      trend: trend('cost_cents_brl', RISING_MEANS_NOTHING),
    },
    { key: 'ROI', value: formatRoi(totals.roi) },
  ];
});
</script>

<!-- Sem v-else de propósito: conta sem agente de IA não ganha bloco nenhum
  aqui. Mesmo padrão de SidebarGroup.vue, que silencia o mesmo aviso. -->
<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div
    v-if="isLoading || hasAgents"
    class="flex flex-col m-0.5 px-6 py-5 rounded-xl gap-5 text-n-slate-12 shadow outline-1 outline outline-n-container bg-n-solid-2"
  >
    <div class="flex flex-wrap gap-3 justify-between items-center">
      <div class="flex flex-wrap gap-2 items-baseline">
        <h5 class="mb-0 text-lg font-medium text-n-slate-12">
          {{ label('TITLE') }}
        </h5>
        <!-- Qual janela isto está medindo. Sem isso, um número de 30 dias
          sentado em cima de uma página ao vivo lê como se fosse de hoje. -->
        <span class="text-[13px] text-n-slate-11">
          {{ label('PERIOD') }}
        </span>
      </div>
      <router-link
        :to="reportUrl"
        class="text-[13px] font-medium text-n-slate-11 hover:text-n-slate-12"
      >
        {{ label('OPEN') }}
      </router-link>
    </div>

    <div
      v-if="isLoading"
      class="flex gap-2 items-center py-4 text-sm text-n-slate-11"
    >
      <Spinner />
      {{ label('LOADING') }}
    </div>

    <div
      v-else
      class="grid grid-cols-2 gap-x-6 gap-y-4 md:grid-cols-3 xl:grid-cols-6"
    >
      <div
        v-for="metric in metrics"
        :key="metric.key"
        class="flex flex-col gap-1"
      >
        <span class="text-[13px] text-n-slate-11">
          {{ label(metric.key) }}
        </span>
        <div class="flex flex-wrap gap-x-2 gap-y-0.5 items-baseline">
          <!-- Um passo abaixo do painel completo. Em seis colunas dentro de um
            container de 1024px, "R$ 4.820,50" em text-2xl encosta na borda e
            quebra depois do "R$", que é a pior forma de escrever dinheiro. -->
          <span class="text-xl font-medium text-n-slate-12">
            {{ metric.value }}
          </span>
          <span
            v-if="metric.trend"
            class="flex gap-1 items-center text-[12px] font-medium tabular-nums"
            :class="metric.trend.tone"
            :title="label('COMPARISON')"
          >
            <span aria-hidden="true">{{ metric.trend.arrow }}</span>
            {{ metric.trend.label }}
          </span>
        </div>
      </div>
    </div>
  </div>
</template>
