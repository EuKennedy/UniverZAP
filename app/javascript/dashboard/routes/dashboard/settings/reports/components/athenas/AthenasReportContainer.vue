<script setup>
/**
 * The AI section of Relatórios.
 *
 * Everything measurable about the agents already existed and every bit of it
 * was per agent, behind the edit screen of one of them. An operator running
 * three agents had three places to look and nowhere to ask which of them earns
 * its keep. This is that place.
 *
 * The period selector sits above everything it scopes and nowhere else: a
 * filter inside a chart card scopes one card and leaves the reader comparing a
 * week against a quarter without being told.
 */
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import AthenasAPI from 'dashboard/api/athenas';
import Spinner from 'shared/components/Spinner.vue';
import AthenasSummary from './AthenasSummary.vue';
import AthenasBarChart from './AthenasBarChart.vue';
import AthenasQualityPanel from './AthenasQualityPanel.vue';
import AthenasAgentTable from './AthenasAgentTable.vue';

const { t } = useI18n();

const PERIODS = [7, 30, 90];

const report = ref(null);
const days = ref(30);
const isLoading = ref(false);
const failed = ref(false);

const money = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
});
const decimal = new Intl.NumberFormat('pt-BR');

const fetchReport = async () => {
  isLoading.value = true;
  failed.value = false;
  try {
    const { data } = await AthenasAPI.accountReport({ days: days.value });
    report.value = data;
  } catch (error) {
    failed.value = true;
  } finally {
    isLoading.value = false;
  }
};

onMounted(fetchReport);
watch(days, fetchReport);

// An account that has never created an agent gets nothing rather than a wall of
// zeroes: a panel full of R$ 0,00 reads like a broken product, not an unused
// one.
const hasAgents = computed(() => (report.value?.agents || []).length > 0);

const dayLabel = iso => {
  const [, month, day] = iso.split('-');
  return `${day}/${month}`;
};

const repliesSeries = computed(() =>
  (report.value?.daily || []).map(row => ({
    key: row.date,
    label: dayLabel(row.date),
    axisLabel: dayLabel(row.date),
    value: row.replies,
    display: decimal.format(row.replies),
  }))
);

const spendSeries = computed(() =>
  (report.value?.daily || []).map(row => ({
    key: row.date,
    label: dayLabel(row.date),
    axisLabel: dayLabel(row.date),
    value: row.cost_cents_brl,
    display: money.format((row.cost_cents_brl || 0) / 100),
  }))
);

const hourSeries = computed(() =>
  (report.value?.hourly || []).map(row => ({
    key: row.hour,
    label: `${String(row.hour).padStart(2, '0')}h`,
    axisLabel: `${String(row.hour).padStart(2, '0')}h`,
    value: row.replies,
    display: decimal.format(row.replies),
  }))
);
</script>

<template>
  <div
    class="flex flex-col m-0.5 px-6 py-5 rounded-xl gap-5 text-n-slate-12 shadow outline-1 outline outline-n-container bg-n-solid-2"
  >
    <header class="flex flex-wrap gap-4 justify-between items-start">
      <div class="flex flex-col gap-1">
        <h3 class="m-0 text-lg font-medium text-n-slate-12">
          {{ t('ATHENAS_REPORT.TITLE') }}
        </h3>
        <p class="m-0 max-w-2xl text-sm text-n-slate-11">
          {{ t('ATHENAS_REPORT.SUBTITLE') }}
        </p>
      </div>
      <div class="flex flex-shrink-0 gap-1 items-center">
        <button
          v-for="period in PERIODS"
          :key="period"
          type="button"
          class="px-2.5 h-7 text-[13px] rounded-md transition-colors"
          :class="
            days === period
              ? 'bg-n-alpha-2 text-n-slate-12 font-medium'
              : 'text-n-slate-11 hover:bg-n-alpha-1'
          "
          @click="days = period"
        >
          {{ t('ATHENAS_REPORT.DAYS', { n: period }) }}
        </button>
      </div>
    </header>

    <div v-if="failed" class="flex flex-col gap-2 items-start">
      <p class="m-0 text-sm text-n-slate-11">
        {{ t('ATHENAS_REPORT.FAILED') }}
      </p>
      <button
        type="button"
        class="text-sm font-medium text-n-slate-12 hover:underline"
        @click="fetchReport"
      >
        {{ t('ATHENAS_REPORT.RETRY') }}
      </button>
    </div>

    <div
      v-else-if="!report && isLoading"
      class="flex gap-2 justify-center items-center py-10 text-sm text-n-slate-11"
    >
      <Spinner />
      {{ t('ATHENAS_REPORT.LOADING') }}
    </div>

    <p v-else-if="report && !hasAgents" class="m-0 text-sm text-n-slate-11">
      {{ t('ATHENAS_REPORT.NO_AGENTS') }}
    </p>

    <!-- Held at reduced opacity while the next period loads, rather than
      swapped for a skeleton: a spinner here would collapse the card and jump
      the whole page every time somebody changes the range. -->
    <div
      v-else-if="report"
      class="flex flex-col gap-6 transition-opacity"
      :class="{ 'opacity-50': isLoading }"
    >
      <AthenasSummary :report="report" />

      <!-- Two charts and never one with two scales: replies and reais are
        different units, and aligning them on a shared axis would invent a
        relationship the numbers never claimed. -->
      <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <AthenasBarChart
          :title="t('ATHENAS_REPORT.CHART.REPLIES')"
          :points="repliesSeries"
          bar-class="bg-n-blue-9"
          :axis-header="t('ATHENAS_REPORT.CHART.DAY')"
          :value-header="t('ATHENAS_REPORT.CHART.REPLIES')"
        />
        <AthenasBarChart
          :title="t('ATHENAS_REPORT.CHART.SPEND')"
          :points="spendSeries"
          bar-class="bg-n-teal-9"
          :axis-header="t('ATHENAS_REPORT.CHART.DAY')"
          :value-header="t('ATHENAS_REPORT.CHART.SPEND')"
        />
      </div>

      <div class="flex flex-col gap-2">
        <AthenasBarChart
          :title="t('ATHENAS_REPORT.CHART.HOURLY')"
          :points="hourSeries"
          bar-class="bg-n-iris-9"
          :axis-header="t('ATHENAS_REPORT.CHART.HOUR')"
          :value-header="t('ATHENAS_REPORT.CHART.REPLIES')"
        />
        <!-- Which clock these hours are on. Without it the quietest hour of the
          night reads as the busiest hour of the afternoon and nobody can tell. -->
        <p class="m-0 text-[12px] text-n-slate-11">
          {{ t('ATHENAS_REPORT.CHART.TIMEZONE', { zone: report.timezone }) }}
        </p>
      </div>

      <AthenasQualityPanel
        :flags="report.flags"
        :quality="report.quality"
        :leads="report.leads"
      />

      <AthenasAgentTable :agents="report.agents" />
    </div>
  </div>
</template>
