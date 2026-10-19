<script setup>
/**
 * Relatórios > Leads por anúncio.
 *
 * Cada linha é um anúncio Click-to-WhatsApp (ID lido do bloco que a WAHA cola
 * na primeira mensagem) com quantas conversas abriu no período, quantas foram
 * respondidas e resolvidas e, se o operador escolher uma etiqueta de meta
 * (ex.: agendado), quantas chegaram lá.
 */
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import ReportHeader from './components/ReportHeader.vue';
import ReportFilters from './components/ReportFilters.vue';
import ReportsAPI from 'dashboard/api/reports';

const { t } = useI18n();
const store = useStore();

const rows = ref([]);
const isLoading = ref(false);
const from = ref(0);
const to = ref(0);
const conversionLabel = ref('');

const labels = computed(() => store.getters['labels/getLabels'] || []);
const hasConversion = computed(() => Boolean(conversionLabel.value));

const totals = computed(() =>
  rows.value.reduce(
    (acc, row) => ({
      leads: acc.leads + row.leads,
      replied: acc.replied + row.replied,
      resolved: acc.resolved + row.resolved,
      converted: acc.converted + (row.converted || 0),
    }),
    { leads: 0, replied: 0, resolved: 0, converted: 0 }
  )
);

// Already wrapped in parentheses so the template holds no raw text.
const rate = (part, total) =>
  total ? `(${Math.round((part / total) * 100)}%)` : '';

const fetchReport = async () => {
  if (!from.value || !to.value) return;
  isLoading.value = true;
  try {
    const { data } = await ReportsAPI.getAdLeadsReport({
      from: from.value,
      to: to.value,
      conversionLabel: conversionLabel.value,
    });
    rows.value = data;
  } catch {
    useAlert(t('REPORT.DATA_FETCHING_FAILED'));
  } finally {
    isLoading.value = false;
  }
};

const onFilterChange = ({ from: since, to: until }) => {
  from.value = since;
  to.value = until;
  fetchReport();
};

onMounted(() => store.dispatch('labels/get'));
</script>

<template>
  <ReportHeader
    :header-title="$t('AD_LEADS_REPORTS.HEADER')"
    :header-description="$t('AD_LEADS_REPORTS.DESCRIPTION')"
  />
  <div class="flex flex-col gap-4 pb-6">
    <div class="flex flex-wrap items-end gap-4">
      <ReportFilters
        :show-group-by="false"
        :show-business-hours="false"
        :show-entity-filter="false"
        @filter-change="onFilterChange"
      />
      <label class="flex flex-col gap-1 text-sm text-n-slate-11">
        {{ $t('AD_LEADS_REPORTS.CONVERSION_LABEL') }}
        <select
          v-model="conversionLabel"
          class="h-10 min-w-64 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm text-n-slate-12"
          @change="fetchReport"
        >
          <option value="">
            {{ $t('AD_LEADS_REPORTS.NO_CONVERSION_LABEL') }}
          </option>
          <option v-for="label in labels" :key="label.id" :value="label.title">
            {{ label.title }}
          </option>
        </select>
      </label>
    </div>

    <div class="overflow-x-auto rounded-xl border border-n-weak bg-n-solid-1">
      <table class="w-full text-sm">
        <thead class="bg-n-solid-2 border-b border-n-container text-n-slate-11">
          <tr>
            <th class="px-4 py-3 text-left font-medium">
              {{ $t('AD_LEADS_REPORTS.COLUMNS.AD') }}
            </th>
            <th class="px-4 py-3 text-right font-medium">
              {{ $t('AD_LEADS_REPORTS.COLUMNS.LEADS') }}
            </th>
            <th class="px-4 py-3 text-right font-medium">
              {{ $t('AD_LEADS_REPORTS.COLUMNS.REPLIED') }}
            </th>
            <th class="px-4 py-3 text-right font-medium">
              {{ $t('AD_LEADS_REPORTS.COLUMNS.RESOLVED') }}
            </th>
            <th v-if="hasConversion" class="px-4 py-3 text-right font-medium">
              {{ $t('AD_LEADS_REPORTS.COLUMNS.CONVERTED') }}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-n-container">
          <tr v-if="!isLoading && !rows.length">
            <td
              class="px-4 py-6 text-center text-n-slate-11"
              :colspan="hasConversion ? 5 : 4"
            >
              {{ $t('AD_LEADS_REPORTS.NO_RECORDS') }}
            </td>
          </tr>
          <tr v-for="row in rows" :key="row.ad_id" class="text-n-slate-12">
            <td class="px-4 py-3">
              <div class="flex flex-col">
                <span class="font-medium">{{ row.title || row.ad_id }}</span>
                <span class="text-xs text-n-slate-11">
                  {{ $t('AD_LEADS_REPORTS.AD_ID', { id: row.ad_id }) }}
                  <a
                    v-if="row.url"
                    :href="row.url"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="ml-2 text-n-brand hover:underline"
                  >
                    {{ $t('AD_LEADS_REPORTS.VIEW_AD') }}
                  </a>
                </span>
              </div>
            </td>
            <td class="px-4 py-3 text-right">{{ row.leads }}</td>
            <td class="px-4 py-3 text-right">
              {{ row.replied }}
              <span class="text-xs text-n-slate-11">
                {{ rate(row.replied, row.leads) }}
              </span>
            </td>
            <td class="px-4 py-3 text-right">{{ row.resolved }}</td>
            <td v-if="hasConversion" class="px-4 py-3 text-right">
              {{ row.converted }}
              <span class="text-xs text-n-slate-11">
                {{ rate(row.converted, row.leads) }}
              </span>
            </td>
          </tr>
        </tbody>
        <tfoot
          v-if="rows.length"
          class="border-t border-n-container font-medium"
        >
          <tr class="text-n-slate-12">
            <td class="px-4 py-3">{{ $t('AD_LEADS_REPORTS.TOTAL') }}</td>
            <td class="px-4 py-3 text-right">{{ totals.leads }}</td>
            <td class="px-4 py-3 text-right">{{ totals.replied }}</td>
            <td class="px-4 py-3 text-right">{{ totals.resolved }}</td>
            <td v-if="hasConversion" class="px-4 py-3 text-right">
              {{ totals.converted }}
              <span class="text-xs text-n-slate-11">
                {{ rate(totals.converted, totals.leads) }}
              </span>
            </td>
          </tr>
        </tfoot>
      </table>
    </div>
  </div>
</template>
