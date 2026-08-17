<script setup>
/**
 * "Rodar agora", com o preço na frente.
 *
 * O clique no botão NÃO roda nada. Ele pergunta ao servidor quanto custaria e
 * mostra a conta: quantas conversas entram na análise e quanto isso consome de
 * crédito. Só o segundo clique gasta.
 *
 * Duas etapas em vez de uma porque o crédito é dinheiro do cliente. Um botão
 * que gasta no primeiro clique transforma curiosidade em cobrança, e o cliente
 * descobre o valor depois, na fatura, que é o pior lugar para descobrir.
 *
 * Sem conversa nova para analisar, a confirmação não aparece: em vez de
 * oferecer um gasto que não produz nada, a tela diz que não há o que analisar.
 */
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AiManagerAPI from 'dashboard/api/aiManager';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  formatNumber,
  formatBrlFromCents,
} from 'dashboard/routes/dashboard/settings/reports/components/athenas/summaryFormat';

const emit = defineEmits(['ran']);

const { t } = useI18n();

const isEstimating = ref(false);
const isRunning = ref(false);
const estimate = ref(null);
const error = ref('');
const hasStarted = ref(false);

const isConfirming = computed(() => estimate.value !== null);
const conversations = computed(() => estimate.value?.conversations ?? 0);
const hasWorkToDo = computed(() => conversations.value > 0);

const messageFrom = (caught, fallback) =>
  caught?.response?.data?.error || caught?.message || t(fallback);

const askEstimate = async () => {
  isEstimating.value = true;
  error.value = '';
  hasStarted.value = false;
  try {
    const { data } = await AiManagerAPI.estimateRun();
    estimate.value = data;
  } catch (caught) {
    error.value = messageFrom(caught, 'AI_MANAGER.RUN.ESTIMATE_ERROR');
  } finally {
    isEstimating.value = false;
  }
};

const cancel = () => {
  estimate.value = null;
  error.value = '';
};

const confirm = async () => {
  isRunning.value = true;
  error.value = '';
  try {
    await AiManagerAPI.createRun();
    estimate.value = null;
    hasStarted.value = true;
    emit('ran');
  } catch (caught) {
    error.value = messageFrom(caught, 'AI_MANAGER.RUN.RUN_ERROR');
  } finally {
    isRunning.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col gap-2 items-stretch sm:items-end">
    <Button
      v-if="!isConfirming"
      variant="outline"
      color="slate"
      size="sm"
      icon="i-lucide-play"
      :label="
        isEstimating ? t('AI_MANAGER.RUN.CHECKING') : t('AI_MANAGER.RUN.ACTION')
      "
      :is-loading="isEstimating"
      :disabled="isEstimating || isRunning"
      data-testid="run-now"
      @click="askEstimate"
    />

    <div
      v-if="isConfirming"
      class="flex flex-col gap-2.5 p-3.5 w-full rounded-xl ring-1 sm:w-80 bg-n-solid-1 ring-n-weak"
      data-testid="run-confirm"
    >
      <p
        v-if="hasWorkToDo"
        class="m-0 text-[13px] leading-relaxed text-n-slate-12"
      >
        {{
          t('AI_MANAGER.RUN.CONFIRM', {
            conversations: formatNumber(conversations),
            credits: formatBrlFromCents(estimate.credits_cents_brl),
          })
        }}
      </p>
      <p v-else class="m-0 text-[13px] leading-relaxed text-n-slate-11">
        {{ t('AI_MANAGER.RUN.NOTHING_TO_ANALYSE') }}
      </p>
      <div class="flex flex-wrap gap-2 items-center">
        <Button
          v-if="hasWorkToDo"
          size="sm"
          :label="t('AI_MANAGER.RUN.CONFIRM_ACTION')"
          :is-loading="isRunning"
          :disabled="isRunning"
          data-testid="run-confirm-action"
          @click="confirm"
        />
        <Button
          variant="ghost"
          color="slate"
          size="sm"
          :label="
            hasWorkToDo ? t('AI_MANAGER.RUN.CANCEL') : t('AI_MANAGER.RUN.CLOSE')
          "
          :disabled="isRunning"
          data-testid="run-cancel"
          @click="cancel"
        />
      </div>
    </div>

    <p
      v-if="hasStarted"
      class="m-0 max-w-xs text-[12px] leading-relaxed text-n-teal-11 sm:text-right"
      data-testid="run-started"
    >
      {{ t('AI_MANAGER.RUN.STARTED') }}
    </p>

    <p
      v-if="error"
      class="m-0 max-w-xs text-[12px] leading-relaxed text-n-ruby-11 sm:text-right"
      data-testid="run-error"
    >
      {{ error }}
    </p>
  </div>
</template>
