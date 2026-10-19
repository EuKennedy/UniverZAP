<script setup>
/**
 * Fila e velocidade. Aberta/aguardando/em risco são ao vivo (mesmos campos da
 * fila da lista de conversas: first_reply_created_at, awaiting_reply,
 * waiting_since); a mediana da 1ª resposta e as respondidas são do período.
 */
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { frontendURL } from 'dashboard/helper/URLHelper';
import PanelStat from './PanelStat.vue';
import { formatSeconds, rate, secondsSince } from './panelFormat';

const props = defineProps({
  queue: { type: Object, default: () => ({}) },
  riskMinutes: { type: Number, required: true },
});

const { t } = useI18n();
const route = useRoute();

const atRisk = computed(() => props.queue.at_risk_conversations || []);
const conversationUrl = id =>
  frontendURL(`accounts/${route.params.accountId}/conversations/${id}`);
const unattendedUrl = computed(() =>
  frontendURL(`accounts/${route.params.accountId}/unattended/conversations`)
);
const waitingFor = row => formatSeconds(secondsSince(row.waiting_since), t);
const riskTone = computed(() => (props.queue.at_risk ? 'danger' : 'good'));
</script>

<template>
  <section class="flex flex-col gap-3">
    <div class="flex flex-col">
      <h2 class="text-base font-medium text-n-slate-12">
        {{ $t('PANEL_REPORTS.QUEUE.TITLE') }}
      </h2>
      <p class="text-xs text-n-slate-11 mb-0">
        {{ $t('PANEL_REPORTS.QUEUE.DESCRIPTION', { minutes: riskMinutes }) }}
      </p>
    </div>

    <div class="flex flex-wrap gap-3">
      <PanelStat
        :label="$t('PANEL_REPORTS.QUEUE.OPEN')"
        :value="queue.open ?? 0"
        :hint="$t('PANEL_REPORTS.LIVE')"
      />
      <PanelStat
        :label="$t('PANEL_REPORTS.QUEUE.WAITING')"
        :value="queue.waiting ?? 0"
        :hint="$t('PANEL_REPORTS.QUEUE.WAITING_HINT')"
        :tone="queue.waiting ? 'warning' : 'neutral'"
      />
      <PanelStat
        :label="$t('PANEL_REPORTS.QUEUE.AT_RISK', { minutes: riskMinutes })"
        :value="queue.at_risk ?? 0"
        :hint="$t('PANEL_REPORTS.QUEUE.AT_RISK_HINT')"
        :tone="riskTone"
      />
      <PanelStat
        :label="$t('PANEL_REPORTS.QUEUE.MEDIAN_FIRST_RESPONSE')"
        :value="formatSeconds(queue.median_first_response_seconds, t)"
        :hint="$t('PANEL_REPORTS.QUEUE.MEDIAN_HINT', { n: queue.replied ?? 0 })"
      />
      <PanelStat
        :label="$t('PANEL_REPORTS.QUEUE.REPLIED_IN_PERIOD')"
        :value="rate(queue.replied, queue.created) || '—'"
        :hint="
          $t('PANEL_REPORTS.QUEUE.REPLIED_HINT', {
            replied: queue.replied ?? 0,
            created: queue.created ?? 0,
          })
        "
      />
    </div>

    <div
      v-if="atRisk.length"
      class="overflow-x-auto rounded-xl border border-n-weak bg-n-solid-1"
    >
      <table class="w-full text-sm">
        <thead class="bg-n-solid-2 border-b border-n-container text-n-slate-11">
          <tr>
            <th class="px-4 py-2 text-left font-medium">
              {{ $t('PANEL_REPORTS.QUEUE.COLUMNS.CONTACT') }}
            </th>
            <th class="px-4 py-2 text-left font-medium">
              {{ $t('PANEL_REPORTS.QUEUE.COLUMNS.AGENT') }}
            </th>
            <th class="px-4 py-2 text-right font-medium">
              {{ $t('PANEL_REPORTS.QUEUE.COLUMNS.WAITING_FOR') }}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-n-container">
          <tr v-for="row in atRisk" :key="row.id" class="text-n-slate-12">
            <td class="px-4 py-2">
              <router-link
                :to="conversationUrl(row.id)"
                class="font-medium text-n-brand hover:underline"
              >
                {{ row.contact || $t('PANEL_REPORTS.QUEUE.NO_CONTACT') }}
              </router-link>
              <span class="ml-2 text-xs text-n-slate-11">#{{ row.id }}</span>
            </td>
            <td class="px-4 py-2">
              {{ row.assignee || $t('PANEL_REPORTS.UNASSIGNED') }}
            </td>
            <td class="px-4 py-2 text-right tabular-nums text-n-ruby-11">
              {{ waitingFor(row) }}
            </td>
          </tr>
        </tbody>
      </table>
      <p
        v-if="queue.at_risk > atRisk.length"
        class="px-4 py-2 text-xs text-n-slate-11 mb-0"
      >
        {{
          $t('PANEL_REPORTS.QUEUE.MORE_AT_RISK', {
            n: queue.at_risk - atRisk.length,
          })
        }}
        <router-link :to="unattendedUrl" class="text-n-brand hover:underline">
          {{ $t('PANEL_REPORTS.QUEUE.OPEN_UNATTENDED') }}
        </router-link>
      </p>
    </div>
  </section>
</template>
