<script setup>
/**
 * Um caso encontrado numa conversa, na ordem em que o olho precisa dele.
 *
 * O card inteiro é o link. Não há botão de aprovar, aplicar ou treinar, e isso
 * é a definição do objeto: quem resolve um destes é uma pessoa abrindo a
 * conversa e respondendo o cliente. Dar a ele uma decisão criaria uma segunda
 * fila para manter em dia depois de o problema já ter sido resolvido de
 * verdade, e é assim que um painel útil vira burocracia.
 *
 * A frase vem antes do trecho de propósito. A frase é a conclusão ("a Fernanda
 * está esperando desde ontem") e o trecho é a prova; quem varre a lista lê só
 * as conclusões e só desce ao trecho no caso que o fez parar.
 *
 * Quando alguém já respondeu depois do achado, o card não some: ele apaga.
 * Sumir apagaria o histórico que o operador pediu para ficar gravado, e mantê-lo
 * aceso mandaria atender de novo quem já foi atendido.
 */
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { severityStyle, timeAgo, money } from '../moderationFormat';

const props = defineProps({
  finding: { type: Object, required: true },
});

const { t } = useI18n();
const { accountScopedRoute } = useAccount();

const style = computed(() => severityStyle(props.finding.severity));

// `conversation_display_id` e não `conversation_id`: a URL do Chatwoot usa a
// sequência POR CONTA, e a chave primária abriria a conversa de outro cliente.
const route = computed(() =>
  accountScopedRoute('inbox_conversation', {
    conversation_id: props.finding.conversation_display_id,
  })
);

const when = computed(() => timeAgo(props.finding.occurred_at));

const value = computed(() =>
  props.finding.value_brl > 0 ? money(props.finding.value_brl) : null
);

const answered = computed(() => props.finding.answered_after === true);

const severityLabel = computed(() =>
  t(`AI_MANAGER.MODERATION.SEVERITY.${props.finding.severity.toUpperCase()}`)
);

const authorLabel = computed(() =>
  t(
    `AI_MANAGER.MODERATION.AUTHOR.${(props.finding.author || 'none').toUpperCase()}`
  )
);

// De onde a conclusão veio. Fica visível porque o operador tem direito de saber
// o que foi contado e o que foi interpretado: uma contagem se confere relendo a
// conversa, uma leitura é opinião de um modelo sobre ela.
const sourceLabel = computed(() =>
  t(
    `AI_MANAGER.MODERATION.SOURCE.${(props.finding.source || 'triage').toUpperCase()}`
  )
);
</script>

<template>
  <router-link
    :to="route"
    class="flex flex-col gap-3 p-4 rounded-2xl border border-l-2 transition-colors group bg-n-solid-1 border-n-weak sm:p-5 hover:bg-n-alpha-1"
    :class="[style.rail, answered && 'opacity-55']"
    data-testid="moderation-card"
  >
    <header class="flex flex-wrap gap-x-2.5 gap-y-1.5 items-center">
      <span
        class="inline-flex gap-1.5 items-center px-2 py-0.5 text-[11px] font-medium rounded-full ring-1"
        :class="style.chip"
        data-testid="severity"
      >
        <span class="size-3" :class="style.icon" aria-hidden="true" />
        {{ severityLabel }}
      </span>

      <span
        v-if="finding.contact_name"
        class="text-[13px] font-medium text-n-slate-12"
        data-testid="contact"
      >
        {{ finding.contact_name }}
      </span>

      <span v-if="when" class="text-[12px] tabular-nums text-n-slate-11">
        {{ when }}
      </span>

      <span
        v-if="value"
        class="px-1.5 py-0.5 text-[11px] font-medium rounded-md tabular-nums bg-n-solid-2 text-n-slate-12"
        data-testid="value"
      >
        {{ value }}
      </span>

      <span
        v-if="answered"
        class="inline-flex gap-1 items-center px-2 py-0.5 ml-auto text-[11px] font-medium rounded-full bg-n-alpha-2 text-n-teal-11"
        data-testid="answered"
      >
        <span class="i-lucide-check size-3" aria-hidden="true" />
        {{ t('AI_MANAGER.MODERATION.ANSWERED') }}
      </span>
    </header>

    <p
      class="m-0 text-[15px] font-medium leading-snug tracking-tight text-n-slate-12"
      data-testid="detail"
    >
      {{ finding.detail || finding.title }}
    </p>

    <!-- O trecho é sempre texto que existe na conversa. Quando o modelo devolve
      uma citação que não confere, o servidor troca pela última mensagem real do
      cliente antes de gravar: nenhuma aspa inventada chega até aqui. -->
    <blockquote
      v-if="finding.excerpt"
      class="pl-3 m-0 text-[13px] italic leading-relaxed border-l-2 text-n-slate-11 border-n-strong"
      data-testid="excerpt"
    >
      {{ finding.excerpt }}
    </blockquote>

    <footer
      class="flex flex-wrap gap-x-2 gap-y-1 items-center text-[11px] text-n-slate-10"
    >
      <span data-testid="case">{{ finding.title }}</span>
      <span class="rounded-full size-0.5 bg-n-slate-8" aria-hidden="true" />
      <span data-testid="author">{{ authorLabel }}</span>
      <span class="rounded-full size-0.5 bg-n-slate-8" aria-hidden="true" />
      <span data-testid="source">{{ sourceLabel }}</span>
      <span
        class="inline-flex gap-1 items-center ml-auto font-medium transition-colors text-n-slate-11 group-hover:text-n-slate-12"
      >
        {{ t('AI_MANAGER.MODERATION.OPEN') }}
        <span class="i-lucide-arrow-right size-3" aria-hidden="true" />
      </span>
    </footer>
  </router-link>
</template>
