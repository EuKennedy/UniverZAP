<script setup>
/**
 * Por atendente. Atribuídas/respondidas/resolvidas/convertidas e a mediana
 * da 1ª resposta são do período, pelo atendente atual da conversa;
 * aguardando e em risco são a fila ao vivo.
 */
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatSeconds, rate } from './panelFormat';

const props = defineProps({
  agents: { type: Array, default: () => [] },
  conversionLabel: { type: String, default: '' },
  riskMinutes: { type: Number, required: true },
});

const { t } = useI18n();
const pct = (part, total) => (total ? `(${rate(part, total)})` : '');

// Agents with nothing in the period and nothing in the queue stay behind a
// toggle: on a big account they would bury the four names that matter.
const showIdle = ref(false);
const isIdle = row => !row.assigned && !row.waiting && !row.at_risk;
const idleCount = computed(() => props.agents.filter(isIdle).length);
const rows = computed(() =>
  showIdle.value ? props.agents : props.agents.filter(row => !isIdle(row))
);
</script>

<template>
  <section class="flex flex-col gap-3">
    <div class="flex flex-col">
      <h2 class="text-base font-medium text-n-slate-12">
        {{ $t('PANEL_REPORTS.AGENTS.TITLE') }}
      </h2>
      <p class="text-xs text-n-slate-11 mb-0">
        {{ $t('PANEL_REPORTS.AGENTS.DESCRIPTION') }}
      </p>
    </div>

    <div class="overflow-x-auto rounded-xl border border-n-weak bg-n-solid-1">
      <table class="w-full text-sm">
        <thead class="bg-n-solid-2 border-b border-n-container text-n-slate-11">
          <tr>
            <th class="px-4 py-2 text-left font-medium">
              {{ $t('PANEL_REPORTS.AGENTS.COLUMNS.AGENT') }}
            </th>
            <th class="px-4 py-2 text-right font-medium">
              {{ $t('PANEL_REPORTS.AGENTS.COLUMNS.ASSIGNED') }}
            </th>
            <th class="px-4 py-2 text-right font-medium">
              {{ $t('PANEL_REPORTS.AGENTS.COLUMNS.REPLIED') }}
            </th>
            <th class="px-4 py-2 text-right font-medium">
              {{ $t('PANEL_REPORTS.AGENTS.COLUMNS.RESOLVED') }}
            </th>
            <th v-if="conversionLabel" class="px-4 py-2 text-right font-medium">
              {{ $t('PANEL_REPORTS.AGENTS.COLUMNS.CONVERTED') }}
            </th>
            <th class="px-4 py-2 text-right font-medium">
              {{ $t('PANEL_REPORTS.AGENTS.COLUMNS.FIRST_RESPONSE') }}
            </th>
            <th class="px-4 py-2 text-right font-medium">
              {{ $t('PANEL_REPORTS.AGENTS.COLUMNS.WAITING') }}
            </th>
            <th class="px-4 py-2 text-right font-medium">
              {{
                $t('PANEL_REPORTS.AGENTS.COLUMNS.AT_RISK', {
                  minutes: riskMinutes,
                })
              }}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-n-container">
          <tr v-if="!rows.length">
            <td
              class="px-4 py-6 text-center text-n-slate-11"
              :colspan="conversionLabel ? 8 : 7"
            >
              {{ $t('PANEL_REPORTS.AGENTS.EMPTY') }}
            </td>
          </tr>
          <tr
            v-for="row in rows"
            :key="row.agent_id ?? 'unassigned'"
            class="text-n-slate-12"
            :class="{ 'text-n-slate-11 italic': row.agent_id === null }"
          >
            <td class="px-4 py-2 font-medium">
              {{ row.name || $t('PANEL_REPORTS.UNASSIGNED') }}
            </td>
            <td class="px-4 py-2 text-right tabular-nums">
              {{ row.assigned }}
            </td>
            <td class="px-4 py-2 text-right tabular-nums">
              {{ row.replied }}
              <span class="text-xs text-n-slate-11">
                {{ pct(row.replied, row.assigned) }}
              </span>
            </td>
            <td class="px-4 py-2 text-right tabular-nums">
              {{ row.resolved }}
            </td>
            <td
              v-if="conversionLabel"
              class="px-4 py-2 text-right tabular-nums text-n-teal-11"
            >
              {{ row.converted }}
              <span class="text-xs text-n-slate-11">
                {{ pct(row.converted, row.assigned) }}
              </span>
            </td>
            <td class="px-4 py-2 text-right tabular-nums">
              {{ formatSeconds(row.median_first_response_seconds, t) }}
            </td>
            <td
              class="px-4 py-2 text-right tabular-nums"
              :class="{ 'text-n-amber-11': row.waiting }"
            >
              {{ row.waiting }}
            </td>
            <td
              class="px-4 py-2 text-right tabular-nums"
              :class="{ 'text-n-ruby-11 font-semibold': row.at_risk }"
            >
              {{ row.at_risk }}
            </td>
          </tr>
        </tbody>
      </table>
      <button
        v-if="idleCount"
        type="button"
        class="w-full px-4 py-2 text-left text-xs text-n-slate-11 hover:text-n-slate-12 border-t border-n-container"
        @click="showIdle = !showIdle"
      >
        {{
          $t(
            showIdle
              ? 'PANEL_REPORTS.AGENTS.HIDE_IDLE'
              : 'PANEL_REPORTS.AGENTS.SHOW_IDLE',
            { n: idleCount }
          )
        }}
      </button>
    </div>
  </section>
</template>
