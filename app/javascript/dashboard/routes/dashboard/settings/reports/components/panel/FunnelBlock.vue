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
import { useAdmin } from 'dashboard/composables/useAdmin';
import AdNamesAPI from 'dashboard/api/adNames';
import PanelStat from './PanelStat.vue';
import { rate } from './panelFormat';

const props = defineProps({
  byAd: { type: Array, default: () => [] },
  byAgent: { type: Array, default: () => [] },
  byCustomer: { type: Array, default: () => [] },
  conversionLabel: { type: String, default: '' },
});

const { t } = useI18n();
const { isAdmin } = useAdmin();

// WhatsApp only hands over the ad id, so an admin names each ad here (or the
// name copied from Ads Manager shows up). Saved names live on the account and
// override the local row right away.
const renamed = ref({});
const editing = ref(null);
const draft = ref({ name: '', campaign: '' });
const saving = ref(false);

const adName = row => renamed.value[row.ad_id] || row;

function startEdit(row) {
  const current = adName(row);
  editing.value = row.ad_id;
  draft.value = { name: current.title || '', campaign: current.campaign || '' };
}

async function saveName(row) {
  saving.value = true;
  try {
    const { data } = await AdNamesAPI.save(row.ad_id, draft.value);
    renamed.value = {
      ...renamed.value,
      [row.ad_id]: {
        title: data.name || null,
        campaign: data.campaign || null,
      },
    };
    editing.value = null;
  } finally {
    saving.value = false;
  }
}
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
  if (view.value === 'ad')
    return adName(row).title || t('PANEL_REPORTS.FUNNEL.UNNAMED_AD');
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
              <form
                v-if="view === 'ad' && editing === row.ad_id"
                class="flex flex-col gap-1.5 max-w-md"
                @submit.prevent="saveName(row)"
              >
                <input
                  v-model="draft.name"
                  class="px-2 py-1 text-sm rounded-md bg-n-alpha-1 text-n-slate-12"
                  :placeholder="$t('PANEL_REPORTS.FUNNEL.NAME_PLACEHOLDER')"
                  autofocus
                />
                <input
                  v-model="draft.campaign"
                  class="px-2 py-1 text-xs rounded-md bg-n-alpha-1 text-n-slate-12"
                  :placeholder="$t('PANEL_REPORTS.FUNNEL.CAMPAIGN_PLACEHOLDER')"
                />
                <div class="flex gap-2">
                  <button
                    type="submit"
                    class="px-3 py-1 text-xs font-medium rounded-md bg-brand-gradient text-[#06131C]"
                    :disabled="saving"
                  >
                    {{ $t('PANEL_REPORTS.FUNNEL.SAVE_NAME') }}
                  </button>
                  <button
                    type="button"
                    class="px-3 py-1 text-xs rounded-md text-n-slate-11 hover:bg-n-alpha-2"
                    @click="editing = null"
                  >
                    {{ $t('PANEL_REPORTS.FUNNEL.CANCEL') }}
                  </button>
                </div>
              </form>
              <div v-else class="flex flex-col">
                <span class="group flex items-center gap-1.5 font-semibold">
                  <span
                    :class="{
                      'text-n-slate-10 italic font-normal':
                        view === 'ad' && !adName(row).title,
                    }"
                  >
                    {{ rowTitle(row) }}
                  </span>
                  <button
                    v-if="view === 'ad' && isAdmin"
                    type="button"
                    class="i-lucide-pencil size-3.5 text-n-slate-10 opacity-0 group-hover:opacity-100 hover:text-n-slate-12"
                    :title="$t('PANEL_REPORTS.FUNNEL.RENAME')"
                    @click="startEdit(row)"
                  />
                </span>
                <span
                  v-if="view === 'ad' && adName(row).campaign"
                  class="text-xs text-n-slate-11"
                >
                  {{
                    $t('PANEL_REPORTS.FUNNEL.CAMPAIGN', {
                      name: adName(row).campaign,
                    })
                  }}
                </span>
                <span v-if="view === 'ad'" class="text-xs text-n-slate-10">
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
