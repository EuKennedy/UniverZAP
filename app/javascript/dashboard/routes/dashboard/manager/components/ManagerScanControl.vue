<script setup>
/**
 * "Analisar conversas", com a janela e o preço na frente.
 *
 * O primeiro clique NÃO gasta. Ele roda só a triagem, que é consulta, e mostra
 * a conta: quantas conversas a leitura vai receber e quanto isso consome. Só o
 * segundo clique chama modelo. Um botão que gasta no primeiro clique transforma
 * curiosidade em cobrança, e o cliente descobre o valor na fatura, que é o pior
 * lugar para descobrir.
 *
 * A janela fica AQUI e não junto dos filtros da lista, e a distinção é a coisa
 * mais fácil de errar nesta tela: esta escolhe o que a leitura vai analisar e
 * custa dinheiro; a de lá fatia o que já foi analisado e é de graça. Vizinhas,
 * o operador ia trocar as duas e pagar de novo por uma conversa que já leu.
 */
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AiManagerAPI from 'dashboard/api/aiManager';
import Button from 'dashboard/components-next/button/Button.vue';
import { centsToBRL } from '../moderationFormat';

defineProps({
  isScanning: { type: Boolean, default: false },
});

const emit = defineEmits(['started']);

const { t } = useI18n();

// As mesmas quatro de Ai::Manager::ConversationScan::WINDOWS. Divergir faria a
// tela oferecer uma janela que o servidor recusa e cai no padrão em silêncio.
const WINDOWS = [
  { hours: 24, key: 'H24' },
  { hours: 72, key: 'D3' },
  { hours: 168, key: 'D7' },
  { hours: 720, key: 'D30' },
];

const hours = ref(24);
const isEstimating = ref(false);
const isStarting = ref(false);
const estimate = ref(null);
const error = ref('');

const isConfirming = computed(() => estimate.value !== null);
const willRead = computed(() => estimate.value?.will_read ?? 0);
const notRead = computed(() =>
  Math.max((estimate.value?.candidates ?? 0) - willRead.value, 0)
);
const hasWorkToDo = computed(() => willRead.value > 0);

const messageFrom = (caught, fallback) =>
  caught?.response?.data?.error || caught?.message || t(fallback);

const pickWindow = value => {
  hours.value = value;
  estimate.value = null;
};

const askEstimate = async () => {
  isEstimating.value = true;
  error.value = '';
  try {
    const { data } = await AiManagerAPI.estimateScan(hours.value);
    estimate.value = data;
  } catch (caught) {
    error.value = messageFrom(
      caught,
      'AI_MANAGER.MODERATION.RUN.ESTIMATE_ERROR'
    );
  } finally {
    isEstimating.value = false;
  }
};

const cancel = () => {
  estimate.value = null;
  error.value = '';
};

const confirm = async () => {
  isStarting.value = true;
  error.value = '';
  try {
    const { data } = await AiManagerAPI.createScan(hours.value);
    estimate.value = null;
    emit('started', data);
  } catch (caught) {
    error.value = messageFrom(caught, 'AI_MANAGER.MODERATION.RUN.START_ERROR');
  } finally {
    isStarting.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col gap-2.5 items-stretch sm:items-end">
    <div class="flex flex-wrap gap-2 items-center sm:justify-end">
      <span class="text-[12px] text-n-slate-11">
        {{ t('AI_MANAGER.MODERATION.RUN.WINDOW_LABEL') }}
      </span>
      <div class="flex gap-1 items-center p-0.5 rounded-lg bg-n-alpha-2">
        <button
          v-for="option in WINDOWS"
          :key="option.hours"
          type="button"
          class="px-2.5 py-1 rounded-md text-[12px] font-medium transition-colors tabular-nums"
          :class="
            hours === option.hours
              ? 'bg-n-solid-1 text-n-slate-12 ring-1 ring-n-weak'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          :disabled="isScanning"
          :data-testid="`scan-window-${option.hours}`"
          @click="pickWindow(option.hours)"
        >
          {{ t(`AI_MANAGER.MODERATION.RUN.WINDOWS.${option.key}`) }}
        </button>
      </div>
    </div>

    <Button
      v-if="!isConfirming && !isScanning"
      variant="outline"
      color="slate"
      size="sm"
      icon="i-lucide-scan-search"
      :label="
        isEstimating
          ? t('AI_MANAGER.MODERATION.RUN.CHECKING')
          : t('AI_MANAGER.MODERATION.RUN.ACTION')
      "
      :is-loading="isEstimating"
      :disabled="isEstimating"
      data-testid="scan-start"
      @click="askEstimate"
    />

    <div
      v-if="isConfirming && !isScanning"
      class="flex flex-col gap-2.5 p-3.5 w-full rounded-xl ring-1 sm:w-96 bg-n-solid-1 ring-n-weak"
      data-testid="scan-confirm"
    >
      <p
        v-if="hasWorkToDo"
        class="m-0 text-[13px] leading-relaxed text-n-slate-12"
      >
        {{
          t('AI_MANAGER.MODERATION.RUN.CONFIRM', {
            read: willRead,
            scanned: estimate.scanned,
            cost: centsToBRL(estimate.cost_cents_brl),
          })
        }}
      </p>
      <!-- O que fica de fora do teto aparece em número. Uma varredura que corta
        em silêncio se apresenta como completa, e é assim que alguém conclui que
        está tudo bem quando não está. -->
      <p
        v-if="hasWorkToDo && notRead > 0"
        class="m-0 text-[12px] leading-relaxed text-n-amber-11"
        data-testid="scan-capped"
      >
        {{ t('AI_MANAGER.MODERATION.RUN.CAPPED', { n: notRead }) }}
      </p>
      <p
        v-if="!hasWorkToDo"
        class="m-0 text-[13px] leading-relaxed text-n-slate-11"
      >
        {{
          t('AI_MANAGER.MODERATION.RUN.NOTHING', {
            found: estimate.triage_findings,
          })
        }}
      </p>
      <div class="flex flex-wrap gap-2 items-center">
        <Button
          v-if="hasWorkToDo"
          size="sm"
          :label="t('AI_MANAGER.MODERATION.RUN.CONFIRM_ACTION')"
          :is-loading="isStarting"
          :disabled="isStarting"
          data-testid="scan-confirm-action"
          @click="confirm"
        />
        <Button
          variant="ghost"
          color="slate"
          size="sm"
          :label="
            hasWorkToDo
              ? t('AI_MANAGER.MODERATION.RUN.CANCEL')
              : t('AI_MANAGER.MODERATION.RUN.CLOSE')
          "
          :disabled="isStarting"
          data-testid="scan-cancel"
          @click="cancel"
        />
      </div>
    </div>

    <div
      v-if="isScanning"
      class="inline-flex gap-2 items-center px-3 py-1.5 rounded-lg ring-1 bg-n-alpha-2 ring-n-weak"
      data-testid="scan-running"
    >
      <span
        class="i-lucide-loader-circle size-3.5 animate-spin text-n-slate-11"
        aria-hidden="true"
      />
      <span class="text-[12px] text-n-slate-11">
        {{ t('AI_MANAGER.MODERATION.RUN.RUNNING') }}
      </span>
    </div>

    <p
      v-if="error"
      class="m-0 max-w-sm text-[12px] leading-relaxed text-n-ruby-11 sm:text-right"
      data-testid="scan-error"
    >
      {{ error }}
    </p>
  </div>
</template>
