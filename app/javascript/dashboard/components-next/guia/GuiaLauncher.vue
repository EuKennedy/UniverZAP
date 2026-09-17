<script setup>
/**
 * A estrela do canto inferior direito: o ponto único de ajuda e de IA.
 *
 * Substitui dois botões que dividiam a mesma coluna. O "?" abria um menu com
 * dois links estáticos, um deles para /docs — o manual que o Guia agora leu e
 * responde em conversa. A bolha do copiloto ficava logo abaixo, e o painel dele
 * (380x600) ainda passava por cima dos dois. Três alvos no mesmo canto para uma
 * pessoa que só queria perguntar uma coisa.
 *
 * O copiloto continua existindo e é aberto daqui: dentro de uma conversa ele
 * mora no painel lateral, e duplicá-lo aqui criaria duas janelas discordando
 * sobre a mesma conversa.
 */
import { ref, computed, nextTick, useTemplateRef } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { emitter } from 'shared/helpers/mitt';
import AthenasAPI from 'dashboard/api/athenas';
import Icon from 'next/icon/Icon.vue';
import { useOnboardingState } from 'dashboard/composables/useOnboardingState';
import { ONBOARDING_TOUR_EVENTS } from 'dashboard/components-next/onboarding/onboardingSteps';

const { t } = useI18n();
const route = useRoute();
const { uiSettings, updateUISettings } = useUISettings();
const { setLastStepIndex, resetDismiss } = useOnboardingState();

const isOpen = ref(false);
const messages = ref([]);
const draft = ref('');
const threadId = ref(null);
const assistantId = ref(null);
const isSending = ref(false);
const scrollerRef = useTemplateRef('scrollerRef');

// Some nas telas onde ninguém está usando o produto ainda.
const isHidden = computed(() =>
  /^(login|signup|reset|password|onboarding_setup)/.test(route.name || '')
);

// Perguntas tiradas das seções que o manual realmente tem. Um estado vazio que
// sugere o que o Guia não sabe responder ensina, na primeira tentativa, que não
// vale perguntar.
const suggestions = computed(() => [
  t('GUIA.SUGGESTIONS.WHATSAPP'),
  t('GUIA.SUGGESTIONS.CAMPAIGN'),
  t('GUIA.SUGGESTIONS.CHATFLOW'),
]);

const scrollToBottom = async () => {
  await nextTick();
  const el = scrollerRef.value;
  if (el) el.scrollTop = el.scrollHeight;
};

const toggle = () => {
  isOpen.value = !isOpen.value;
};

const resolveAssistant = async () => {
  if (assistantId.value) return assistantId.value;
  const { data } = await AthenasAPI.getWikiAssistant();
  assistantId.value = data.id;
  return assistantId.value;
};

const ask = async text => {
  const trimmed = (text ?? draft.value).trim();
  if (!trimmed || isSending.value) return;

  isSending.value = true;
  draft.value = '';
  const optimistic = {
    id: `tmp-${messages.value.length}`,
    role: 'user',
    content: trimmed,
  };
  messages.value = [...messages.value, optimistic];
  await scrollToBottom();

  try {
    const id = await resolveAssistant();
    if (threadId.value) {
      const { data } = await AthenasAPI.sendThreadMessage(
        threadId.value,
        trimmed
      );
      messages.value = messages.value
        .filter(m => m.id !== optimistic.id)
        .concat([data.user_message, data.assistant_message].filter(Boolean));
    } else {
      const { data } = await AthenasAPI.createThread({
        assistantId: id,
        title: t('GUIA.THREAD_TITLE'),
        initialMessage: trimmed,
      });
      threadId.value = data.id;
      messages.value = data.messages || [];
    }
    await scrollToBottom();
  } catch (error) {
    messages.value = messages.value.filter(m => m.id !== optimistic.id);
    useAlert(error.response?.data?.error || error.message);
  } finally {
    isSending.value = false;
  }
};

// O ponteiro do passo e a marca de dispensa precisam ser zerados ANTES do
// evento, senão o tour "recomeça" de onde a pessoa parou — que é exatamente o
// que ela não quer quando clica em refazer.
const retakeTour = async () => {
  isOpen.value = false;
  await setLastStepIndex(0);
  resetDismiss();
  emitter.emit(ONBOARDING_TOUR_EVENTS.START, { restart: true });
};

const openDocs = () => {
  isOpen.value = false;
  window.open('/docs', '_blank', 'noopener');
};

// O copiloto é outro agente e outro assunto: ele fala da conversa do cliente.
// Abrir o painel dele daqui é o que permite este canto ter um alvo só.
const openCopilot = () => {
  isOpen.value = false;
  updateUISettings({
    is_copilot_panel_open: !uiSettings.value.is_copilot_panel_open,
    is_contact_sidebar_open: false,
  });
};
</script>

<template>
  <div v-if="!isHidden" class="fixed bottom-4 z-50 ltr:right-4 rtl:left-4">
    <Transition
      enter-active-class="motion-safe:transition-all motion-safe:duration-200"
      enter-from-class="opacity-0 translate-y-2 scale-95"
      leave-active-class="motion-safe:transition-all motion-safe:duration-150"
      leave-to-class="opacity-0 translate-y-2 scale-95"
    >
      <div
        v-if="isOpen"
        class="flex absolute bottom-full flex-col mb-3 w-96 max-w-[calc(100vw-2rem)] h-[520px] max-h-[calc(100vh-6rem)] rounded-2xl border shadow-2xl origin-bottom-right overflow-hidden border-n-weak/70 bg-n-surface-1 ltr:right-0 rtl:left-0"
      >
        <div
          class="flex gap-3 items-center px-4 py-3 border-b border-n-weak/60 bg-gradient-to-br from-n-teal-9/15 to-transparent"
        >
          <span
            class="grid rounded-xl size-9 place-content-center bg-gradient-to-br from-n-teal-9 to-n-teal-10 text-white"
          >
            <Icon icon="i-lucide-sparkles" class="size-4" />
          </span>
          <div class="flex flex-col min-w-0">
            <p class="m-0 text-sm font-semibold leading-tight text-n-slate-12">
              {{ t('GUIA.TITLE') }}
            </p>
            <p class="m-0 text-xs leading-snug text-n-slate-11">
              {{ t('GUIA.SUBTITLE') }}
            </p>
          </div>
          <button
            type="button"
            class="ml-auto rounded-lg p-1.5 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
            :aria-label="t('GUIA.CLOSE')"
            @click="toggle"
          >
            <Icon icon="i-lucide-x" class="size-4" />
          </button>
        </div>

        <div
          ref="scrollerRef"
          class="overflow-y-auto flex-1 px-4 py-3 space-y-3"
        >
          <template v-if="!messages.length">
            <p class="m-0 text-xs leading-relaxed text-n-slate-11">
              {{ t('GUIA.EMPTY') }}
            </p>
            <button
              v-for="question in suggestions"
              :key="question"
              type="button"
              class="px-3 py-2 w-full text-xs text-left rounded-xl border transition-colors border-n-weak/60 text-n-slate-12 hover:bg-n-alpha-2"
              @click="ask(question)"
            >
              {{ question }}
            </button>
          </template>

          <div
            v-for="message in messages"
            :key="message.id"
            class="flex"
            :class="message.role === 'user' ? 'justify-end' : 'justify-start'"
          >
            <p
              class="m-0 px-3 py-2 max-w-[85%] text-sm leading-relaxed whitespace-pre-wrap rounded-2xl"
              :class="
                message.role === 'user'
                  ? 'bg-n-teal-9 text-white'
                  : 'bg-n-alpha-2 text-n-slate-12'
              "
            >
              {{ message.content }}
            </p>
          </div>

          <p v-if="isSending" class="m-0 text-xs text-n-slate-11">
            {{ t('GUIA.THINKING') }}
          </p>
        </div>

        <div class="px-3 pt-2 pb-3 border-t border-n-weak/60">
          <div class="flex gap-2 items-end">
            <textarea
              v-model="draft"
              rows="1"
              :placeholder="t('GUIA.PLACEHOLDER')"
              class="flex-1 px-3 py-2 text-sm rounded-xl border resize-none border-n-weak/60 bg-n-alpha-1 text-n-slate-12 placeholder:text-n-slate-10"
              @keydown.enter.exact.prevent="ask()"
            />
            <button
              type="button"
              class="grid rounded-xl size-9 place-content-center bg-n-teal-9 text-white disabled:opacity-40"
              :disabled="isSending || !draft.trim()"
              :aria-label="t('GUIA.SEND')"
              @click="ask()"
            >
              <Icon icon="i-lucide-arrow-up" class="size-4" />
            </button>
          </div>

          <div class="flex flex-wrap gap-1 mt-2">
            <button
              type="button"
              class="px-2 py-1 text-xs rounded-lg text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
              @click="openCopilot"
            >
              {{ t('GUIA.ACTIONS.COPILOT') }}
            </button>
            <button
              type="button"
              class="px-2 py-1 text-xs rounded-lg text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
              @click="retakeTour"
            >
              {{ t('GUIA.ACTIONS.TOUR') }}
            </button>
            <button
              type="button"
              class="px-2 py-1 text-xs rounded-lg text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
              @click="openDocs"
            >
              {{ t('GUIA.ACTIONS.DOCS') }}
            </button>
          </div>
        </div>
      </div>
    </Transition>

    <button
      type="button"
      class="grid rounded-full shadow-lg ring-1 transition-all size-12 place-content-center bg-gradient-to-br from-n-teal-9 to-n-teal-10 text-white ring-white/10 hover:brightness-110"
      :aria-label="t('GUIA.OPEN')"
      data-testid="guia-launcher"
      @click="toggle"
    >
      <Icon icon="i-lucide-sparkles" class="size-5" />
    </button>
  </div>
</template>
