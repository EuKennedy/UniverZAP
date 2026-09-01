<script setup>
/**
 * O moderador: as conversas que precisam de alguém hoje.
 *
 * A aba tem duas metades que parecem uma só e não são, e entender a diferença é
 * entender a feature inteira:
 *
 * 1. ANALISAR custa. Roda a triagem, manda o que sobrou para o modelo ler, e
 *    GRAVA o resultado. Acontece quando alguém clica, nunca sozinha.
 * 2. FILTRAR é de graça. Fatia o que já está gravado. Trocar de "24 horas" para
 *    "30 dias" aqui não lê nada de novo: mostra o que as leituras anteriores já
 *    encontraram naquele intervalo.
 *
 * É por isso que os filtros ficam longe do botão de analisar, e por isso que o
 * botão diz o preço antes. Um operador que confunde as duas paga de novo por
 * uma conversa que já leu.
 *
 * A varredura é assíncrona porque chama modelo uma vez por conversa e leva
 * minutos. A tela pergunta de tempos em tempos se acabou, e recarrega a lista
 * quando acabar.
 */
import { computed, onMounted, onBeforeUnmount, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import AiManagerAPI from 'dashboard/api/aiManager';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';

import ManagerConversationCard from './ManagerConversationCard.vue';
import ManagerScanControl from './ManagerScanControl.vue';
import { centsToBRL, timeAgo } from '../moderationFormat';

const { t } = useI18n();

// De quanto em quanto tempo a tela pergunta se a varredura acabou. Três
// segundos porque uma leitura de sessenta conversas leva minutos: mais rápido
// seria bater no servidor à toa, mais lento faria a lista parecer travada
// depois de a leitura já ter terminado.
const POLL_MS = 3000;

const DAY_FILTERS = [
  { days: 1, key: 'D1' },
  { days: 3, key: 'D3' },
  { days: 7, key: 'D7' },
  { days: 30, key: 'D30' },
  { days: null, key: 'ALL' },
];

const AUTHOR_FILTERS = [
  { value: '', key: 'ALL' },
  { value: 'agent', key: 'AGENT' },
  { value: 'human', key: 'HUMAN' },
  { value: 'none', key: 'NONE' },
];

const isLoading = ref(true);
const loadError = ref('');
const data = ref(null);
const days = ref(1);
const author = ref('');
const caseKey = ref('');
const scan = ref(null);
let poller = null;

const findings = computed(() => data.value?.findings || []);
const counts = computed(() => data.value?.counts || {});
const cases = computed(() => data.value?.cases || []);
const lastScan = computed(() => scan.value || data.value?.last_scan || null);
const isScanning = computed(() => lastScan.value?.status === 'running');

const messageFrom = (caught, fallback) =>
  caught?.response?.data?.error || caught?.message || t(fallback);

const load = async () => {
  loadError.value = '';
  try {
    const { data: payload } = await AiManagerAPI.listFindings({
      days: days.value ?? undefined,
      author: author.value || undefined,
      caseKey: caseKey.value || undefined,
    });
    data.value = payload;
    // A varredura local só sobrevive enquanto está rodando. Depois disso quem
    // manda é a que veio do servidor, que é a fonte do custo e do que ficou de
    // fora do teto de leitura.
    if (payload.last_scan?.status !== 'running') scan.value = null;
  } catch (caught) {
    loadError.value = messageFrom(caught, 'AI_MANAGER.MODERATION.LOAD_ERROR');
  } finally {
    isLoading.value = false;
  }
};

const applyFilter = async patch => {
  if ('days' in patch) days.value = patch.days;
  if ('author' in patch) author.value = patch.author;
  if ('caseKey' in patch) caseKey.value = patch.caseKey;
  isLoading.value = true;
  await load();
};

const stopPolling = () => {
  if (poller) clearInterval(poller);
  poller = null;
};

const poll = async () => {
  if (!scan.value?.id) {
    stopPolling();
    return;
  }
  try {
    const { data: payload } = await AiManagerAPI.getScan(scan.value.id);
    scan.value = payload;
    if (payload.status !== 'running') {
      stopPolling();
      await load();
    }
  } catch {
    // Uma falha de rede no meio da espera não pode apagar a varredura da tela:
    // ela continua rodando no servidor. A próxima batida tenta de novo.
  }
};

const onScanStarted = started => {
  scan.value = started;
  stopPolling();
  poller = setInterval(poll, POLL_MS);
};

const scanLine = computed(() => {
  const done = lastScan.value;
  if (!done || done.status === 'running') return '';
  if (done.status === 'failed') return t('AI_MANAGER.MODERATION.SCAN_FAILED');

  return t('AI_MANAGER.MODERATION.SCAN_SUMMARY', {
    when: timeAgo(done.finished_at),
    scanned: done.conversations_scanned,
    read: done.conversations_read,
    cost: centsToBRL(done.cost_cents_brl),
  });
});

onMounted(load);
onBeforeUnmount(stopPolling);
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="flex flex-col gap-3 justify-between sm:flex-row sm:items-start">
      <div class="flex flex-col gap-1">
        <p class="m-0 max-w-xl text-[13px] leading-relaxed text-n-slate-11">
          {{ t('AI_MANAGER.MODERATION.INTRO') }}
        </p>
        <p
          v-if="scanLine"
          class="m-0 text-[12px] tabular-nums text-n-slate-11"
          data-testid="scan-line"
        >
          {{ scanLine }}
        </p>
      </div>
      <ManagerScanControl :is-scanning="isScanning" @started="onScanStarted" />
    </div>

    <!-- Os filtros da LISTA. Não custam nada e não leem nada: fatiam o que as
      leituras anteriores já gravaram. -->
    <div class="flex flex-col gap-2">
      <div class="flex flex-wrap gap-2 items-center">
        <span class="text-[12px] text-n-slate-11">
          {{ t('AI_MANAGER.MODERATION.FILTERS.PERIOD') }}
        </span>
        <div
          class="flex flex-wrap gap-1 items-center p-0.5 rounded-lg bg-n-alpha-2"
        >
          <button
            v-for="option in DAY_FILTERS"
            :key="option.key"
            type="button"
            class="px-2.5 py-1 rounded-md text-[12px] font-medium transition-colors tabular-nums"
            :class="
              days === option.days
                ? 'bg-n-solid-1 text-n-slate-12 ring-1 ring-n-weak'
                : 'text-n-slate-11 hover:text-n-slate-12'
            "
            :data-testid="`filter-days-${option.key}`"
            @click="applyFilter({ days: option.days })"
          >
            {{ t(`AI_MANAGER.MODERATION.FILTERS.DAYS.${option.key}`) }}
          </button>
        </div>
      </div>

      <div class="flex flex-wrap gap-2 items-center">
        <span class="text-[12px] text-n-slate-11">
          {{ t('AI_MANAGER.MODERATION.FILTERS.AUTHOR') }}
        </span>
        <div
          class="flex flex-wrap gap-1 items-center p-0.5 rounded-lg bg-n-alpha-2"
        >
          <button
            v-for="option in AUTHOR_FILTERS"
            :key="option.key"
            type="button"
            class="px-2.5 py-1 rounded-md text-[12px] font-medium transition-colors"
            :class="
              author === option.value
                ? 'bg-n-solid-1 text-n-slate-12 ring-1 ring-n-weak'
                : 'text-n-slate-11 hover:text-n-slate-12'
            "
            :data-testid="`filter-author-${option.key}`"
            @click="applyFilter({ author: option.value })"
          >
            {{ t(`AI_MANAGER.MODERATION.FILTERS.AUTHORS.${option.key}`) }}
            <span
              v-if="option.value && counts.by_author?.[option.value]"
              class="ml-1 opacity-60"
            >
              {{ counts.by_author[option.value] }}
            </span>
          </button>
        </div>

        <select
          v-model="caseKey"
          class="px-2.5 py-1 text-[12px] rounded-lg ring-1 bg-n-alpha-2 text-n-slate-12 ring-n-weak"
          data-testid="filter-case"
          @change="applyFilter({ caseKey })"
        >
          <option value="">
            {{ t('AI_MANAGER.MODERATION.FILTERS.ALL_CASES') }}
          </option>
          <option v-for="item in cases" :key="item.key" :value="item.key">
            {{ item.title }}
          </option>
        </select>
      </div>
    </div>

    <p
      v-if="loadError"
      class="m-0 text-[13px] text-n-ruby-11"
      data-testid="moderation-error"
    >
      {{ loadError }}
    </p>

    <div v-if="isLoading" class="flex justify-center py-16">
      <Spinner />
    </div>

    <!-- Lista vazia tem dois significados opostos, e a tela precisa dizer qual.
      Nunca ter analisado é diferente de ter analisado e não achado nada, e as
      duas mostrariam a mesma tela em branco. -->
    <div
      v-else-if="!findings.length"
      class="flex flex-col gap-2 items-center py-16 text-center rounded-2xl ring-1 bg-n-solid-1 ring-n-weak"
      data-testid="moderation-empty"
    >
      <span
        class="grid rounded-2xl ring-1 size-12 bg-gradient-to-br from-n-teal-3 to-transparent ring-n-weak place-content-center"
      >
        <span
          class="size-6 text-n-teal-11"
          :class="lastScan ? 'i-lucide-check-check' : 'i-lucide-scan-search'"
          aria-hidden="true"
        />
      </span>
      <h3 class="m-0 text-[15px] font-medium text-n-slate-12">
        {{
          lastScan
            ? t('AI_MANAGER.MODERATION.EMPTY_TITLE')
            : t('AI_MANAGER.MODERATION.NEVER_TITLE')
        }}
      </h3>
      <p class="m-0 max-w-sm text-[13px] leading-relaxed text-n-slate-11">
        {{
          lastScan
            ? t('AI_MANAGER.MODERATION.EMPTY_BODY')
            : t('AI_MANAGER.MODERATION.NEVER_BODY')
        }}
      </p>
    </div>

    <div v-else class="flex flex-col gap-3">
      <div class="flex flex-wrap gap-2 justify-between items-center">
        <p class="m-0 text-[12px] tabular-nums text-n-slate-11">
          {{ t('AI_MANAGER.MODERATION.COUNT', { n: counts.total || 0 }) }}
        </p>
        <Button
          variant="ghost"
          color="slate"
          size="sm"
          icon="i-lucide-refresh-cw"
          :label="t('AI_MANAGER.MODERATION.REFRESH')"
          data-testid="moderation-refresh"
          @click="applyFilter({})"
        />
      </div>
      <ManagerConversationCard
        v-for="finding in findings"
        :key="finding.id"
        :finding="finding"
      />
    </div>
  </div>
</template>
