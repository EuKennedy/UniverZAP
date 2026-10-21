<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ChatflowsAPI from 'dashboard/api/chatflows';

// O robô desta conversa, logo acima do composer: "Fluxo Agendamento em
// andamento · esperando resposta [Pausar robô]" ou "Robô pausado — você
// assumiu [Retomar robô]". Sem fluxo nem pausa, não aparece.
const { t } = useI18n();

const currentChat = useMapGetter('getSelectedChat');
const conversationId = computed(() => currentChat.value?.id);

const state = ref(null);
const isBusy = ref(false);

const execution = computed(() => state.value?.execution || null);
const paused = computed(() => Boolean(state.value?.paused));
const visible = computed(() => paused.value || Boolean(execution.value));

const stepLabel = computed(() => {
  const exec = execution.value;
  if (!exec) return '';
  if (exec.resume_at) return t('CHATFLOW.BOT_BANNER.WAITING_TIMER');
  return (
    exec.node_name ||
    t(`CHATFLOW.NODE.KIND.${(exec.node_kind || 'send_message').toUpperCase()}`)
  );
});

const fetchState = async () => {
  if (!conversationId.value) return;
  try {
    const { data } = await ChatflowsAPI.conversationState(conversationId.value);
    state.value = data;
  } catch {
    state.value = null;
  }
};

const toggle = async () => {
  isBusy.value = true;
  try {
    const wasPaused = paused.value;
    const { data } = wasPaused
      ? await ChatflowsAPI.resumeConversation(conversationId.value)
      : await ChatflowsAPI.pauseConversation(conversationId.value);
    state.value = data;
    useAlert(
      t(
        wasPaused
          ? 'CHATFLOW.BOT_BANNER.RESUMED_OK'
          : 'CHATFLOW.BOT_BANNER.PAUSED_OK'
      )
    );
  } catch {
    useAlert(t('CHATFLOW.BOT_BANNER.ERROR'));
  } finally {
    isBusy.value = false;
  }
};

watch(
  conversationId,
  () => {
    state.value = null;
    fetchState();
  },
  { immediate: true }
);

// Mensagem nova (dela ou de um atendente) pode avançar, encerrar ou pausar o
// fluxo: recarrega um instante depois, quando o job do motor já rodou.
const lastMessageId = computed(() => {
  const messages = currentChat.value?.messages || [];
  return messages.length ? messages[messages.length - 1].id : null;
});
watch(lastMessageId, (id, previous) => {
  if (id && previous && id !== previous) setTimeout(fetchState, 1500);
});
</script>

<template>
  <div
    v-if="visible"
    class="flex items-center gap-2 px-3 py-1.5 mx-2 rounded-lg border"
    :class="
      paused ? 'bg-n-amber-2 border-n-amber-5' : 'bg-n-iris-2 border-n-iris-5'
    "
    data-testid="chatflow-bot-banner"
  >
    <span
      class="size-4 shrink-0"
      :class="
        paused
          ? 'i-lucide-pause-circle text-n-amber-11'
          : 'i-lucide-workflow text-n-iris-11'
      "
    />
    <span class="flex-1 min-w-0 text-xs truncate text-n-slate-12">
      <template v-if="paused">
        {{
          state.paused_by
            ? t('CHATFLOW.BOT_BANNER.PAUSED_BY', { name: state.paused_by })
            : t('CHATFLOW.BOT_BANNER.PAUSED')
        }}
      </template>
      <template v-else>
        {{
          t('CHATFLOW.BOT_BANNER.RUNNING', {
            flow: execution.chatflow_name,
            step: stepLabel,
          })
        }}
      </template>
    </span>
    <NextButton
      xs
      :color="paused ? 'teal' : 'slate'"
      :variant="paused ? 'solid' : 'ghost'"
      :icon="paused ? 'i-lucide-play' : 'i-lucide-pause'"
      :label="
        paused
          ? t('CHATFLOW.BOT_BANNER.RESUME')
          : t('CHATFLOW.BOT_BANNER.PAUSE')
      "
      :is-loading="isBusy"
      data-testid="chatflow-bot-toggle"
      @click="toggle"
    />
  </div>
</template>
