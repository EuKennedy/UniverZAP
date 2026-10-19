<script setup>
/**
 * Anúncio → conversão. Totais do período e a mesma tabela vista por anúncio,
 * por atendente (quem recebeu o lead) ou por cliente nova × recorrente
 * (etiqueta cliente-recorrente). Os números vêm do
 * V2::Reports::AdLeadsBuilder: leads, respondidas (first_reply_created_at),
 * resolvidas (status) e convertidas (etiqueta escolhida na página).
 */
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import PanelStat from './PanelStat.vue';
import { rate } from './panelFormat';

const props = defineProps({
  byAd: { type: Array, default: () => [] },
  byAgent: { type: Array, default: () => [] },
  byCustomer: { type: Array, default: () => [] },
  conversionLabel: { type: String, default: '' },
});

const { t } = useI18n();
const VIEWS = ['ad', 'agent', 'customer'];
const view = ref('ad');

const hasConversion = computed(() => Boolean(props.conversionLabel));
const rows = computed(
  () =>
    ({ ad: props.byAd, agent: props.byAgent, customer: props.byCustomer })[
      view.value
    ]
);

const totals = computed(() =>
  props.byAd.reduce(
    (acc, row) => ({
      leads: acc.leads + row.leads,
      replied: acc.replied + row.replied,
      resolved: acc.resolved + row.resolved,
      converted: acc.converted + (row.converted || 0),
    }),
    { leads: 0, replied: 0, resolved: 0, converted: 0 }
  )
);

const rowTitle = row => {
  if (view.value === 'ad') return row.title || row.ad_id;
  if (view.value === 'customer')
    return t(`PANEL_REPORTS.FUNNEL.CUSTOMER_${row.customer.toUpperCase()}`);
  return row.title || t('PANEL_REPORTS.UNASSIGNED');
};
const rowKey = row => {
  if (view.value === 'ad') return row.ad_id;
  if (view.value === 'customer') return `customer-${row.customer}`;
  return `agent-${row.agent_id}`;
};
const pct = (part, total) => (total ? `(${rate(part, total)})` : '');
</script>

<template>
  <section class="flex flex-col gap-3">
    <div class="flex flex-wrap items-baseline justify-between gap-2">
      <div class="flex flex-col">
        <h2 class="text-base font-medium text-n-slate-12">
          {{ $t('PANEL_REPORTS.FUNNEL.TITLE') }}
        </h2>
        <p class="text-xs text-n-slate-11 mb-0">
          {{ $t('PANEL_REPORTS.FUNNEL.DESCRIPTION') }}
        </p>
      </div>
      <div
        class="inline-flex rounded-lg border border-n-weak bg-n-solid-1 p-0.5 text-xs"
      >
        <button
          v-for="option in VIEWS"
          :key="option"
          type="button"
          class="rounded-md px-3 py-1 font-medium"
          :class="
            view === option
              ? 'bg-n-solid-3 text-n-slate-12'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="view = option"
        >
          {{ $t(`PANEL_REPORTS.FUNNEL.VIEW_${option.toUpperCase()}`) }}
        </button>
      </div>
    </div>

    <div class="flex flex-wrap gap-3">
      <PanelStat
        :label="$t('PANEL_REPORTS.FUNNEL.LEADS')"
        :value="totals.leads"
        :hint="$t('PANEL_REPORTS.FUNNEL.LEADS_HINT')"
      />
      <PanelStat
        :label="$t('PANEL_REPORTS.FUNNEL.REPLIED')"
        :value="totals.replied"
        :hint="pct(totals.replied, totals.leads)"
      />
      <PanelStat
        :label="$t('PANEL_REPORTS.FUNNEL.RESOLVED')"
        :value="totals.resolved"
        :hint="pct(totals.resolved, totals.leads)"
      />
      <PanelStat
        :label="$t('PANEL_REPORTS.FUNNEL.CONVERTED')"
        :value="hasConversion ? totals.converted : '—'"
        :hint="
          hasConversion
            ? pct(totals.converted, totals.leads)
            : $t('PANEL_REPORTS.PICK_CONVERSION_LABEL')
        "
        tone="good"
      />
    </div>

    <div class="overflow-x-auto rounded-xl border border-n-weak bg-n-solid-1">
      <table class="w-full text-sm">
        <thead class="bg-n-solid-2 border-b border-n-container text-n-slate-11">
          <tr>
            <th class="px-4 py-2 text-left font-medium">
              {{ $t(`PANEL_REPORTS.FUNNEL.COLUMN_${view.toUpperCase()}`) }}
            </th>
            <th class="px-4 py-2 text-right font-medium">
              {{ $t('PANEL_REPORTS.FUNNEL.LEADS') }}
            </th>
            <th class="px-4 py-2 text-right font-medium">
              {{ $t('PANEL_REPORTS.FUNNEL.REPLIED') }}
            </th>
            <th class="px-4 py-2 text-right font-medium">
              {{ $t('PANEL_REPORTS.FUNNEL.RESOLVED') }}
            </th>
            <th v-if="hasConversion" class="px-4 py-2 text-right font-medium">
              {{ $t('PANEL_REPORTS.FUNNEL.CONVERTED') }}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-n-container">
          <tr v-if="!rows.length">
            <td
              class="px-4 py-6 text-center text-n-slate-11"
              :colspan="hasConversion ? 5 : 4"
            >
              {{ $t('PANEL_REPORTS.FUNNEL.EMPTY') }}
            </td>
          </tr>
          <tr v-for="row in rows" :key="rowKey(row)" class="text-n-slate-12">
            <td class="px-4 py-2">
              <div class="flex flex-col">
                <span class="font-medium">{{ rowTitle(row) }}</span>
                <span v-if="view === 'ad'" class="text-xs text-n-slate-11">
                  {{ $t('PANEL_REPORTS.FUNNEL.AD_ID', { id: row.ad_id }) }}
                  <a
                    v-if="row.url"
                    :href="row.url"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="ml-2 text-n-brand hover:underline"
                  >
                    {{ $t('PANEL_REPORTS.FUNNEL.VIEW_AD_LINK') }}
                  </a>
                </span>
              </div>
            </td>
            <td class="px-4 py-2 text-right tabular-nums">{{ row.leads }}</td>
            <td class="px-4 py-2 text-right tabular-nums">
              {{ row.replied }}
              <span class="text-xs text-n-slate-11">
                {{ pct(row.replied, row.leads) }}
              </span>
            </td>
            <td class="px-4 py-2 text-right tabular-nums">
              {{ row.resolved }}
            </td>
            <td
              v-if="hasConversion"
              class="px-4 py-2 text-right tabular-nums text-n-teal-11"
            >
              {{ row.converted }}
              <span class="text-xs text-n-slate-11">
                {{ pct(row.converted, row.leads) }}
              </span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>
</template>
