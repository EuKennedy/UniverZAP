<script setup>
/**
 * "Gerente": a fila de sugestões sobre o agente de IA.
 *
 * Uma FILA e não um painel. Painel se olha, fila se trabalha: cada card é um
 * diagnóstico com a evidência junto e um botão que resolve, e o objeto vai
 * embora quando você decide sobre ele. É o formato que vira hábito, porque tem
 * começo e tem fim. Um painel com os mesmos dados seria olhado na primeira
 * semana e ignorado na terceira.
 *
 * As três notas ficam em cima porque são o contexto da fila, não o produto
 * dela. Quem chega aqui vem decidir sobre sugestões.
 *
 * A página é dona das duas listas e das chamadas que as alteram. Os cards
 * emitem, ela aplica e tira a linha da fila sem recarregar: perder a posição
 * da rolagem a cada decisão é o que torna uma fila insuportável no volume.
 */
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import AiManagerAPI from 'dashboard/api/aiManager';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

import ManagerScoreStrip from '../components/ManagerScoreStrip.vue';
import ManagerDataGap from '../components/ManagerDataGap.vue';
import ManagerSuggestionCard from '../components/ManagerSuggestionCard.vue';
import ManagerRunNow from '../components/ManagerRunNow.vue';
import ManagerChecks from '../components/ManagerChecks.vue';
import { formatMoment } from '../managerFormat';

const { t } = useI18n();

const TABS = ['queue', 'checks'];

const isLoading = ref(true);
const loadError = ref('');
const actionError = ref('');
const overview = ref(null);
const suggestions = ref([]);
const activeTab = ref('queue');
const busyId = ref(null);

const messageFrom = (caught, fallback) =>
  caught?.response?.data?.error || caught?.message || t(fallback);

// Dado insuficiente é a resposta padrão, não o caso raro: enquanto o backend
// não disser que já tem conversa suficiente, a tela não desenha nota nenhuma.
const sufficiency = computed(() => overview.value?.data_sufficiency || {});
const hasEnoughData = computed(() => sufficiency.value.enough === true);

const scores = computed(() => overview.value?.scores || {});
const agents = computed(() => overview.value?.agents || []);
const lastRunAt = computed(() => formatMoment(overview.value?.last_run_at));
const nextRunAt = computed(() => formatMoment(overview.value?.next_run_at));

const pendingCount = computed(() => suggestions.value.length);

// Uma frase montada aqui e não dois pedaços colados no template com um ponto
// no meio: em português a segunda metade só funciona depois de vírgula, e
// separador solto no meio de duas datas é lixo para quem usa leitor de tela.
const scheduleLine = computed(() => {
  if (lastRunAt.value && nextRunAt.value) {
    return t('AI_MANAGER.SCHEDULE_BOTH', {
      last: lastRunAt.value,
      next: nextRunAt.value,
    });
  }
  if (lastRunAt.value) {
    return t('AI_MANAGER.LAST_RUN', { when: lastRunAt.value });
  }
  if (nextRunAt.value) {
    return t('AI_MANAGER.NEXT_RUN', { when: nextRunAt.value });
  }
  return null;
});

const fetchAll = async () => {
  isLoading.value = true;
  loadError.value = '';
  actionError.value = '';
  try {
    const [overviewResponse, queueResponse] = await Promise.all([
      AiManagerAPI.overview(),
      AiManagerAPI.listSuggestions({ status: 'pending' }),
    ]);
    overview.value = overviewResponse.data;
    suggestions.value = queueResponse.data?.payload || [];
  } catch (caught) {
    loadError.value = messageFrom(caught, 'AI_MANAGER.LOAD_ERROR');
  } finally {
    isLoading.value = false;
  }
};

const removeFromQueue = id => {
  suggestions.value = suggestions.value.filter(item => item.id !== id);
};

const approve = async suggestion => {
  busyId.value = suggestion.id;
  actionError.value = '';
  try {
    await AiManagerAPI.approveSuggestion(suggestion.id);
    removeFromQueue(suggestion.id);
  } catch (caught) {
    actionError.value = messageFrom(caught, 'AI_MANAGER.APPROVE_ERROR');
  } finally {
    busyId.value = null;
  }
};

const dismiss = async (suggestion, reason) => {
  busyId.value = suggestion.id;
  actionError.value = '';
  try {
    await AiManagerAPI.dismissSuggestion(suggestion.id, reason);
    removeFromQueue(suggestion.id);
  } catch (caught) {
    actionError.value = messageFrom(caught, 'AI_MANAGER.DISMISS_ERROR');
  } finally {
    busyId.value = null;
  }
};

onMounted(fetchAll);
</script>

<template>
  <div class="flex overflow-auto flex-col w-full h-full bg-n-background">
    <header
      class="flex flex-wrap gap-4 justify-between items-start px-8 py-6 border-b border-n-weak"
    >
      <div class="flex flex-col gap-1">
        <h1 class="m-0 text-xl font-semibold tracking-tight text-n-slate-12">
          {{ t('AI_MANAGER.TITLE') }}
        </h1>
        <p class="m-0 max-w-xl text-sm leading-relaxed text-n-slate-11">
          {{ t('AI_MANAGER.SUBTITLE') }}
        </p>
      </div>

      <div class="flex flex-col gap-2 items-stretch sm:items-end">
        <ManagerRunNow @ran="fetchAll" />
        <!-- Quando ele passou por aqui pela última vez e quando volta. Sem
          isso, uma fila vazia não se distingue de um Gerente parado. -->
        <p
          v-if="scheduleLine"
          class="m-0 text-[12px] tabular-nums text-n-slate-11 sm:text-right"
          data-testid="run-schedule"
        >
          {{ scheduleLine }}
        </p>
      </div>
    </header>

    <div v-if="isLoading" class="flex flex-1 justify-center items-center">
      <Spinner :size="24" />
    </div>

    <div
      v-else-if="loadError"
      class="flex flex-col flex-1 gap-3 justify-center items-center px-8 py-16 text-center"
      data-testid="load-error"
    >
      <p class="m-0 max-w-md text-sm text-n-ruby-11">{{ loadError }}</p>
      <Button
        variant="outline"
        color="slate"
        size="sm"
        :label="t('AI_MANAGER.RETRY')"
        data-testid="retry"
        @click="fetchAll"
      />
    </div>

    <div v-else class="flex flex-col gap-6 px-8 py-6">
      <ManagerDataGap
        v-if="!hasEnoughData"
        :analysed="sufficiency.analysed || 0"
        :needed="sufficiency.needed || 0"
      />
      <ManagerScoreStrip v-else :scores="scores" :agents="agents" />

      <div class="flex gap-1 items-center p-0.5 rounded-lg bg-n-alpha-2 w-fit">
        <button
          v-for="tab in TABS"
          :key="tab"
          type="button"
          class="px-3 py-1 rounded-md text-[12px] font-medium transition-colors tabular-nums"
          :class="
            activeTab === tab
              ? 'bg-n-solid-1 text-n-slate-12 ring-1 ring-n-weak'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          :data-testid="`tab-${tab}`"
          @click="activeTab = tab"
        >
          {{ t(`AI_MANAGER.TABS.${tab.toUpperCase()}`) }}
          <span v-if="tab === 'queue' && pendingCount" class="ml-1 opacity-60">
            {{ pendingCount }}
          </span>
        </button>
      </div>

      <template v-if="activeTab === 'queue'">
        <p
          v-if="actionError"
          class="m-0 text-[13px] text-n-ruby-11"
          data-testid="action-error"
        >
          {{ actionError }}
        </p>

        <!-- Fila vazia é boa notícia e a tela diz isso. Um estado vazio mudo
          lê como tela quebrada, e o operador vai procurar o que não existe. -->
        <div
          v-if="!suggestions.length"
          class="flex flex-col gap-2 items-center py-16 text-center rounded-2xl ring-1 bg-n-solid-1 ring-n-weak"
          data-testid="empty-queue"
        >
          <span
            class="grid rounded-2xl ring-1 size-12 bg-gradient-to-br from-n-teal-3 to-transparent ring-n-weak place-content-center"
          >
            <span class="i-lucide-check-check size-6 text-n-teal-11" />
          </span>
          <h2 class="m-0 text-[15px] font-medium text-n-slate-12">
            {{ t('AI_MANAGER.QUEUE.EMPTY_TITLE') }}
          </h2>
          <p class="m-0 max-w-sm text-[13px] leading-relaxed text-n-slate-11">
            {{ t('AI_MANAGER.QUEUE.EMPTY_BODY') }}
          </p>
          <p
            class="m-0 text-[12px] tabular-nums text-n-slate-11"
            data-testid="empty-last-run"
          >
            {{
              lastRunAt
                ? t('AI_MANAGER.LAST_RUN', { when: lastRunAt })
                : t('AI_MANAGER.NEVER_RAN')
            }}
          </p>
        </div>

        <div v-else class="flex flex-col gap-3">
          <ManagerSuggestionCard
            v-for="suggestion in suggestions"
            :key="suggestion.id"
            :suggestion="suggestion"
            :is-busy="busyId === suggestion.id"
            @approve="approve(suggestion)"
            @dismiss="reason => dismiss(suggestion, reason)"
          />
        </div>
      </template>

      <ManagerChecks v-else />
    </div>
  </div>
</template>
