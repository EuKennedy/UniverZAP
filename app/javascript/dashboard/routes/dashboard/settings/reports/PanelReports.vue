<script setup>
/**
 * Relatórios > Painel: a tela que a dona e a gestora olham todo dia.
 *
 * Três blocos, do mais valioso para o mais operacional: o funil de anúncio
 * (quanto do dinheiro de mídia virou conversa, resposta e agendamento), a
 * fila (quem está esperando e há quanto tempo) e o time (quem responde, quem
 * converte). Tudo vem de um único GET /api/v2/.../reports/dashboard e só de
 * colunas que já existem: custom_attributes do anúncio, first_reply_created_at,
 * awaiting_reply, waiting_since, status e etiquetas.
 *
 * A etiqueta que conta como conversão e o limite de minutos para "em risco"
 * são escolhas da conta, lembradas por usuário nas UI settings.
 */
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useUISettings } from 'dashboard/composables/useUISettings';
import ReportsAPI from 'dashboard/api/reports';
import ReportHeader from './components/ReportHeader.vue';
import ReportFilters from './components/ReportFilters.vue';
import FunnelBlock from './components/panel/FunnelBlock.vue';
import QueueBlock from './components/panel/QueueBlock.vue';
import AgentsBlock from './components/panel/AgentsBlock.vue';

const CONVERSION_LABEL_KEY = 'panel_conversion_label';
const RISK_MINUTES_KEY = 'panel_risk_minutes';
const DEFAULT_CONVERSION_LABEL = 'agendado';
const DEFAULT_RISK_MINUTES = 30;
const RISK_OPTIONS = [15, 30, 60, 120];

const { t } = useI18n();
const store = useStore();
const { uiSettings, updateUISettings } = useUISettings();

const report = ref(null);
const isLoading = ref(false);
const from = ref(0);
const to = ref(0);
// ReportFilters emits the first period before the labels arrive; the first
// request waits for them so the conversion column is right from the start.
const labelsLoaded = ref(false);

const labels = computed(() => store.getters['labels/getLabels'] || []);
const conversionLabel = computed(
  () => uiSettings.value[CONVERSION_LABEL_KEY] ?? DEFAULT_CONVERSION_LABEL
);
const riskMinutes = computed(
  () => Number(uiSettings.value[RISK_MINUTES_KEY]) || DEFAULT_RISK_MINUTES
);

// A etiqueta padrão só vale se existir na conta; senão a coluna fica "não
// medido" até alguém escolher, em vez de contar zero contra uma etiqueta
// que ninguém usa.
const effectiveConversionLabel = computed(() =>
  labels.value.some(label => label.title === conversionLabel.value)
    ? conversionLabel.value
    : ''
);

const fetchReport = async () => {
  if (!from.value || !to.value) return;
  isLoading.value = true;
  try {
    const { data } = await ReportsAPI.getDashboard({
      from: from.value,
      to: to.value,
      conversionLabel: effectiveConversionLabel.value,
      riskMinutes: riskMinutes.value,
    });
    report.value = data;
  } catch {
    useAlert(t('REPORT.DATA_FETCHING_FAILED'));
  } finally {
    isLoading.value = false;
  }
};

const onFilterChange = ({ from: since, to: until }) => {
  from.value = since;
  to.value = until;
  if (labelsLoaded.value) fetchReport();
};

const onConversionLabelChange = event => {
  updateUISettings({ [CONVERSION_LABEL_KEY]: event.target.value });
  fetchReport();
};

const onRiskMinutesChange = event => {
  updateUISettings({ [RISK_MINUTES_KEY]: Number(event.target.value) });
  fetchReport();
};

onMounted(async () => {
  await store.dispatch('labels/get');
  labelsLoaded.value = true;
  fetchReport();
});
</script>

<template>
  <ReportHeader
    :header-title="$t('PANEL_REPORTS.HEADER')"
    :header-description="$t('PANEL_REPORTS.DESCRIPTION')"
  />
  <div class="flex flex-col gap-8 pb-6">
    <div class="flex flex-wrap items-end gap-4">
      <ReportFilters
        :show-group-by="false"
        :show-business-hours="false"
        :show-entity-filter="false"
        @filter-change="onFilterChange"
      />
      <label class="flex flex-col gap-1 text-sm text-n-slate-11">
        {{ $t('PANEL_REPORTS.CONVERSION_LABEL') }}
        <select
          :value="effectiveConversionLabel"
          class="h-10 min-w-56 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm text-n-slate-12"
          @change="onConversionLabelChange"
        >
          <option value="">
            {{ $t('PANEL_REPORTS.NO_CONVERSION_LABEL') }}
          </option>
          <option v-for="label in labels" :key="label.id" :value="label.title">
            {{ label.title }}
          </option>
        </select>
      </label>
      <label class="flex flex-col gap-1 text-sm text-n-slate-11">
        {{ $t('PANEL_REPORTS.RISK_MINUTES') }}
        <select
          :value="riskMinutes"
          class="h-10 min-w-40 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm text-n-slate-12"
          @change="onRiskMinutesChange"
        >
          <option v-for="option in RISK_OPTIONS" :key="option" :value="option">
            {{ $t('PANEL_REPORTS.RISK_OPTION', { minutes: option }) }}
          </option>
        </select>
      </label>
      <span v-if="isLoading" class="pb-3 text-xs text-n-slate-11">
        {{ $t('PANEL_REPORTS.LOADING') }}
      </span>
    </div>

    <template v-if="report">
      <FunnelBlock
        :by-ad="report.funnel.by_ad"
        :by-agent="report.funnel.by_agent"
        :conversion-label="report.conversion_label || ''"
      />
      <QueueBlock :queue="report.queue" :risk-minutes="report.risk_minutes" />
      <AgentsBlock
        :agents="report.agents"
        :conversion-label="report.conversion_label || ''"
        :risk-minutes="report.risk_minutes"
      />
    </template>
  </div>
</template>
