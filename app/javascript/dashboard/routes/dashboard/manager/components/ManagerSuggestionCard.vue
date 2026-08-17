<script setup>
/**
 * Uma sugestão do Gerente, na ordem em que se decide sobre ela.
 *
 * O problema em uma frase, a evidência, o que muda, e só então os botões.
 * A evidência no meio não é enfeite: sem o trecho da conversa e o número que
 * provocou o diagnóstico, aprovar é confiar no parecer de um robô sobre o
 * trabalho de outro robô, e ninguém faz isso duas vezes.
 *
 * O card não fala com a API. Ele emite, e a página aplica: a fila precisa
 * sumir com a linha aprovada sem recarregar, e quem sabe o que é a fila é a
 * página.
 */
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  SEVERITY_CRITICAL,
  TARGET_PROMPT,
  formatMoment,
  proposedText,
  humanizeMetric,
} from '../managerFormat';

const props = defineProps({
  suggestion: { type: Object, required: true },
  isBusy: { type: Boolean, default: false },
});

const emit = defineEmits(['approve', 'dismiss']);

const { t } = useI18n();
const { accountScopedRoute } = useAccount();

// A copy das verificações que já existem mora aqui, e não no backend, porque é
// texto de produto: quem escreve "prometeu um horário e a agenda gravou outro"
// é esta tela. Verificação nova que o servidor invente ainda aparece, com o
// título que ele mandar, em vez de sumir da fila por falta de tradução.
const KNOWN_CHECKS = [
  'promised_time_mismatch',
  'loose_promise',
  'died_on_price',
  'ungrounded_number',
];

const isCritical = computed(
  () => props.suggestion.severity === SEVERITY_CRITICAL
);

// Aprovar memória vale na hora. Aprovar prompt abre uma disputa contra a
// versão atual e pode não virar nada. São duas ações diferentes e a tela não
// pode deixar as duas com a mesma cara.
const isPromptTarget = computed(
  () => props.suggestion.target === TARGET_PROMPT
);

const headline = computed(() => {
  const key = props.suggestion.check_key;
  return KNOWN_CHECKS.includes(key)
    ? t(`AI_MANAGER.CHECK.${key.toUpperCase()}.TITLE`)
    : props.suggestion.title;
});

const evidence = computed(() => props.suggestion.evidence || {});

const metricLine = computed(() => {
  const { metric, value } = evidence.value;
  if (metric === null || metric === undefined) return null;
  return `${humanizeMetric(metric)}: ${value}`;
});

const conversationRoute = computed(() =>
  accountScopedRoute('inbox_conversation', {
    conversation_id: evidence.value.conversation_id,
  })
);

const change = computed(() => proposedText(props.suggestion.proposed));

const createdAt = computed(() => formatMoment(props.suggestion.created_at));

const isDismissing = ref(false);
const reason = ref('');

const canDismiss = computed(() => reason.value.trim().length > 0);

const openDismiss = () => {
  isDismissing.value = true;
};

const cancelDismiss = () => {
  isDismissing.value = false;
  reason.value = '';
};

const confirmDismiss = () => {
  if (!canDismiss.value) return;
  emit('dismiss', reason.value.trim());
};
</script>

<template>
  <article
    class="flex flex-col gap-4 p-5 rounded-2xl border bg-n-solid-1"
    :class="
      isCritical
        ? 'border-n-weak border-l-2 border-l-n-ruby-9'
        : 'border-n-weak'
    "
    data-testid="suggestion-card"
  >
    <header class="flex flex-wrap gap-x-3 gap-y-2 items-center">
      <!-- Ícone, palavra e uma barra na lateral esquerda do card. Crítico não
        pode depender só da cor: quem não separa vermelho de âmbar precisa ver
        a diferença de outro jeito. -->
      <span
        class="inline-flex gap-1.5 items-center px-2 py-0.5 text-[11px] font-medium rounded-full ring-1"
        :class="
          isCritical
            ? 'bg-n-ruby-3 text-n-ruby-11 ring-n-ruby-6'
            : 'bg-n-alpha-2 text-n-slate-11 ring-n-weak'
        "
        data-testid="severity-badge"
      >
        <span
          class="size-3"
          :class="
            isCritical ? 'i-lucide-alert-triangle' : 'i-lucide-circle-dot'
          "
          aria-hidden="true"
        />
        {{
          isCritical
            ? t('AI_MANAGER.CARD.SEVERITY.CRITICAL')
            : t('AI_MANAGER.CARD.SEVERITY.NORMAL')
        }}
      </span>
      <span
        v-if="suggestion.agent_name"
        class="text-[12px] text-n-slate-11"
        data-testid="agent-name"
      >
        {{ suggestion.agent_name }}
      </span>
      <span v-if="createdAt" class="text-[12px] tabular-nums text-n-slate-11">
        {{ createdAt }}
      </span>
    </header>

    <div class="flex flex-col gap-1.5">
      <h3
        class="m-0 text-[15px] font-medium leading-snug tracking-tight text-n-slate-12"
        data-testid="headline"
      >
        {{ headline }}
      </h3>
      <p
        v-if="suggestion.rationale"
        class="m-0 max-w-3xl text-[13px] leading-relaxed text-n-slate-11"
      >
        {{ suggestion.rationale }}
      </p>
    </div>

    <section
      class="flex flex-col gap-2.5 p-3.5 rounded-xl bg-n-alpha-1"
      data-testid="evidence"
    >
      <span
        class="text-[11px] font-medium tracking-wider uppercase text-n-slate-11"
      >
        {{ t('AI_MANAGER.CARD.EVIDENCE') }}
      </span>
      <blockquote
        v-if="evidence.excerpt"
        class="pl-3 m-0 text-[13px] leading-relaxed border-l-2 border-n-weak text-n-slate-12"
        data-testid="evidence-excerpt"
      >
        {{ evidence.excerpt }}
      </blockquote>
      <div class="flex flex-wrap gap-x-3 gap-y-1.5 items-center">
        <span
          v-if="metricLine"
          class="px-2 py-0.5 text-[12px] font-medium rounded-md tabular-nums bg-n-solid-2 text-n-slate-12"
          data-testid="evidence-metric"
        >
          {{ metricLine }}
        </span>
        <router-link
          v-if="evidence.conversation_id"
          :to="conversationRoute"
          class="text-[12px] font-medium text-n-slate-11 hover:text-n-slate-12"
          data-testid="evidence-link"
        >
          {{ t('AI_MANAGER.CARD.OPEN_CONVERSATION') }}
        </router-link>
      </div>
    </section>

    <section class="flex flex-col gap-2" data-testid="change">
      <div class="flex flex-wrap gap-x-2.5 gap-y-1 items-center">
        <span
          class="text-[11px] font-medium tracking-wider uppercase text-n-slate-11"
        >
          {{ t('AI_MANAGER.CARD.CHANGE') }}
        </span>
        <span
          class="inline-flex gap-1.5 items-center px-2 py-0.5 text-[11px] font-medium rounded-full ring-1"
          :class="
            isPromptTarget
              ? 'bg-n-amber-3 text-n-amber-11 ring-n-amber-6'
              : 'bg-n-teal-3 text-n-teal-11 ring-n-teal-6'
          "
          data-testid="target-chip"
        >
          <span
            class="size-3"
            :class="isPromptTarget ? 'i-lucide-swords' : 'i-lucide-brain'"
            aria-hidden="true"
          />
          {{
            isPromptTarget
              ? t('AI_MANAGER.CARD.TARGET.PROMPT')
              : t('AI_MANAGER.CARD.TARGET.TRAINING')
          }}
        </span>
      </div>
      <p
        v-if="change"
        class="m-0 max-w-3xl text-[13px] leading-relaxed whitespace-pre-wrap text-n-slate-12"
        data-testid="change-text"
      >
        {{ change }}
      </p>
      <p
        class="m-0 text-[12px] leading-relaxed text-n-slate-11"
        data-testid="target-effect"
      >
        {{
          isPromptTarget
            ? t('AI_MANAGER.CARD.TARGET.PROMPT_EFFECT')
            : t('AI_MANAGER.CARD.TARGET.TRAINING_EFFECT')
        }}
      </p>
    </section>

    <footer v-if="!isDismissing" class="flex flex-wrap gap-2 items-center">
      <!-- O botão diz o que vai acontecer, não "Aprovar". É o último lugar
        onde a diferença entre valer agora e entrar em disputa ainda cabe. -->
      <Button
        size="sm"
        :label="
          isPromptTarget
            ? t('AI_MANAGER.CARD.APPROVE_PROMPT')
            : t('AI_MANAGER.CARD.APPROVE_TRAINING')
        "
        :is-loading="isBusy"
        :disabled="isBusy"
        data-testid="approve"
        @click="emit('approve')"
      />
      <Button
        variant="ghost"
        color="slate"
        size="sm"
        :label="t('AI_MANAGER.CARD.DISMISS')"
        :disabled="isBusy"
        data-testid="dismiss"
        @click="openDismiss"
      />
    </footer>

    <!-- Dispensar pede motivo. Uma fila que se esvazia sem motivo registrado
      não ensina nada ao Gerente e volta com a mesma sugestão na semana que
      vem. -->
    <footer
      v-else
      class="flex flex-col gap-2.5 p-3.5 rounded-xl ring-1 bg-n-alpha-1 ring-n-weak"
      data-testid="dismiss-panel"
    >
      <label
        class="text-[12px] font-medium text-n-slate-12"
        :for="`dismiss-reason-${suggestion.id}`"
      >
        {{ t('AI_MANAGER.CARD.DISMISS_REASON_LABEL') }}
      </label>
      <input
        :id="`dismiss-reason-${suggestion.id}`"
        v-model="reason"
        type="text"
        class="px-3 py-2 w-full text-[13px] rounded-lg ring-1 bg-n-solid-1 ring-n-weak text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-n-teal-8"
        :placeholder="t('AI_MANAGER.CARD.DISMISS_PLACEHOLDER')"
        data-testid="dismiss-reason"
        @keyup.enter="confirmDismiss"
      />
      <div class="flex flex-wrap gap-2 items-center">
        <Button
          size="sm"
          color="ruby"
          :label="t('AI_MANAGER.CARD.DISMISS_CONFIRM')"
          :disabled="!canDismiss || isBusy"
          :is-loading="isBusy"
          data-testid="dismiss-confirm"
          @click="confirmDismiss"
        />
        <Button
          variant="ghost"
          color="slate"
          size="sm"
          :label="t('AI_MANAGER.CARD.DISMISS_CANCEL')"
          :disabled="isBusy"
          data-testid="dismiss-cancel"
          @click="cancelDismiss"
        />
      </div>
    </footer>
  </article>
</template>
