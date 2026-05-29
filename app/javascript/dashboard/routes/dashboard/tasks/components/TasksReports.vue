<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';

import BarChart from 'shared/components/charts/BarChart.vue';

const { t } = useI18n();
const store = useStore();

const isLoading = ref(false);
const range = ref({
  from: new Date(Date.now() - 29 * 24 * 60 * 60 * 1000)
    .toISOString()
    .slice(0, 10),
  to: new Date().toISOString().slice(0, 10),
});

const data = ref({
  created_vs_completed: [],
  avg_time_to_complete_by_agent: [],
  overdue_rate_by_agent: [],
  open_urgency_distribution: { urgent: 0, high: 0, medium: 0, low: 0, none: 0 },
});

const refresh = async () => {
  isLoading.value = true;
  try {
    const payload = await store.dispatch('tasks/fetchReports', {
      from: range.value.from,
      to: range.value.to,
    });
    data.value = { ...data.value, ...payload };
  } finally {
    isLoading.value = false;
  }
};

const createdVsCompletedChart = computed(() => ({
  labels: data.value.created_vs_completed.map(row => row.date),
  datasets: [
    {
      label: t('TASKS.REPORTS.LABELS.CREATED'),
      backgroundColor: '#4F46E5',
      data: data.value.created_vs_completed.map(row => row.created),
    },
    {
      label: t('TASKS.REPORTS.LABELS.COMPLETED'),
      backgroundColor: '#10B981',
      data: data.value.created_vs_completed.map(row => row.completed),
    },
  ],
}));

const avgTimeChart = computed(() => ({
  labels: data.value.avg_time_to_complete_by_agent.map(row => row.user.name),
  datasets: [
    {
      label: t('TASKS.REPORTS.LABELS.AVG_HOURS'),
      backgroundColor: '#0EA5E9',
      data: data.value.avg_time_to_complete_by_agent.map(row => row.avg_hours),
    },
  ],
}));

const overdueRateChart = computed(() => ({
  labels: data.value.overdue_rate_by_agent.map(row => row.user.name),
  datasets: [
    {
      label: t('TASKS.REPORTS.LABELS.OVERDUE_RATE'),
      backgroundColor: '#F43F5E',
      data: data.value.overdue_rate_by_agent.map(row =>
        Math.round(row.rate * 100)
      ),
    },
  ],
}));

const urgencyChart = computed(() => {
  const distribution = data.value.open_urgency_distribution || {};
  const order = ['urgent', 'high', 'medium', 'low', 'none'];
  return {
    labels: order.map(key => t(`TASKS.URGENCY.${key.toUpperCase()}`)),
    datasets: [
      {
        label: t('TASKS.REPORTS.LABELS.URGENCY_OPEN'),
        backgroundColor: [
          '#DC2626',
          '#EA580C',
          '#F59E0B',
          '#10B981',
          '#94A3B8',
        ],
        data: order.map(key => distribution[key] || 0),
      },
    ],
  };
});

onMounted(refresh);
</script>

<template>
  <section
    class="flex flex-col gap-5 px-6 py-6 overflow-y-auto"
    data-test-id="tasks-reports"
  >
    <header class="flex flex-wrap items-end gap-3 justify-between">
      <div>
        <h2 class="text-[15px] font-semibold text-n-slate-12 tracking-tight">
          {{ t('TASKS.REPORTS.TITLE') }}
        </h2>
        <p class="text-[12px] text-n-slate-10">
          {{ t('TASKS.REPORTS.SUBTITLE') }}
        </p>
      </div>
      <form
        class="flex items-end gap-2"
        data-test-id="tasks-reports-filters"
        @submit.prevent="refresh"
      >
        <label
          class="flex flex-col gap-1 text-[11px] uppercase text-n-slate-10"
        >
          {{ t('TASKS.REPORTS.FROM') }}
          <input
            v-model="range.from"
            type="date"
            class="px-2.5 py-1.5 rounded-md bg-n-alpha-1 ring-1 ring-inset ring-n-weak text-sm text-n-slate-12 outline-none"
          />
        </label>
        <label
          class="flex flex-col gap-1 text-[11px] uppercase text-n-slate-10"
        >
          {{ t('TASKS.REPORTS.TO') }}
          <input
            v-model="range.to"
            type="date"
            class="px-2.5 py-1.5 rounded-md bg-n-alpha-1 ring-1 ring-inset ring-n-weak text-sm text-n-slate-12 outline-none"
          />
        </label>
        <button
          type="submit"
          class="h-9 px-3 text-[12px] rounded-md bg-n-blue-9 text-white hover:bg-n-blue-10"
          data-test-id="tasks-reports-apply"
        >
          {{ t('TASKS.REPORTS.APPLY') }}
        </button>
      </form>
    </header>

    <div
      v-if="isLoading"
      class="flex items-center justify-center py-12 text-n-slate-10"
    >
      <span class="i-lucide-loader-circle size-5 animate-spin" />
    </div>
    <div v-else class="grid grid-cols-1 lg:grid-cols-2 gap-4">
      <article
        class="rounded-xl bg-n-solid-1 ring-1 ring-n-weak p-4"
        data-test-id="tasks-reports-created-vs-completed"
      >
        <h3 class="text-[13px] font-semibold text-n-slate-12 mb-3">
          {{ t('TASKS.REPORTS.CHARTS.CREATED_VS_COMPLETED') }}
        </h3>
        <div class="h-64">
          <BarChart :collection="createdVsCompletedChart" />
        </div>
      </article>

      <article
        class="rounded-xl bg-n-solid-1 ring-1 ring-n-weak p-4"
        data-test-id="tasks-reports-avg-time"
      >
        <h3 class="text-[13px] font-semibold text-n-slate-12 mb-3">
          {{ t('TASKS.REPORTS.CHARTS.AVG_TIME') }}
        </h3>
        <div class="h-64">
          <BarChart :collection="avgTimeChart" />
        </div>
      </article>

      <article
        class="rounded-xl bg-n-solid-1 ring-1 ring-n-weak p-4"
        data-test-id="tasks-reports-overdue-rate"
      >
        <h3 class="text-[13px] font-semibold text-n-slate-12 mb-3">
          {{ t('TASKS.REPORTS.CHARTS.OVERDUE_RATE') }}
        </h3>
        <div class="h-64">
          <BarChart :collection="overdueRateChart" />
        </div>
      </article>

      <article
        class="rounded-xl bg-n-solid-1 ring-1 ring-n-weak p-4"
        data-test-id="tasks-reports-urgency"
      >
        <h3 class="text-[13px] font-semibold text-n-slate-12 mb-3">
          {{ t('TASKS.REPORTS.CHARTS.URGENCY') }}
        </h3>
        <div class="h-64">
          <BarChart :collection="urgencyChart" />
        </div>
      </article>
    </div>
  </section>
</template>
