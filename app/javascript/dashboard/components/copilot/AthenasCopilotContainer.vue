<script setup>
import { computed, nextTick, onMounted, ref, useTemplateRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAthenasAssistant } from 'dashboard/composables/useAthenasAssistant';
import AthenasAssistantsAPI from 'dashboard/api/athenas';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';
import Spinner from 'shared/components/Spinner.vue';

const { t } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();

const currentChat = useMapGetter('getSelectedChat');

const {
  assistants,
  activeAssistant,
  activeAssistantId,
  fetchAssistants,
  setAssistant,
} = useAthenasAssistant();

const threads = ref([]);
const selectedThreadId = ref(null);
const messages = ref([]);
const draft = ref('');
const isSending = ref(false);
const isLoadingThreads = ref(false);
const isLoadingMessages = ref(false);
const isCreatingThread = ref(false);
const messagesContainerRef = useTemplateRef('messagesContainerRef');

const isOpen = computed(() => Boolean(uiSettings.value?.is_copilot_panel_open));
const conversationId = computed(() => currentChat.value?.id || null);

const hasAssistants = computed(() => assistants.value.length > 0);

const closePanel = () => {
  if (!isOpen.value) return;
  updateUISettings({
    is_contact_sidebar_open: false,
    is_copilot_panel_open: false,
  });
};

const scrollToBottom = async () => {
  await nextTick();
  const el = messagesContainerRef.value;
  if (!el) return;
  el.scrollTop = el.scrollHeight;
};

const loadThreads = async () => {
  if (!conversationId.value) {
    threads.value = [];
    return;
  }
  isLoadingThreads.value = true;
  try {
    const response = await AthenasAssistantsAPI.listThreads({
      conversationId: conversationId.value,
    });
    threads.value = response.data || [];
  } catch (error) {
    useAlert(error.response?.data?.error || error.message);
  } finally {
    isLoadingThreads.value = false;
  }
};

const loadThreadMessages = async threadId => {
  if (!threadId) {
    messages.value = [];
    return;
  }
  isLoadingMessages.value = true;
  try {
    const response = await AthenasAssistantsAPI.getThread(threadId);
    messages.value = response.data?.messages || [];
  } catch (error) {
    useAlert(error.response?.data?.error || error.message);
  } finally {
    isLoadingMessages.value = false;
    scrollToBottom();
  }
};

const selectThread = async threadId => {
  selectedThreadId.value = threadId;
  await loadThreadMessages(threadId);
};

const startNewThread = () => {
  selectedThreadId.value = null;
  messages.value = [];
  draft.value = '';
};

const sendMessage = async () => {
  const trimmed = draft.value.trim();
  if (!trimmed || isSending.value) return;
  if (!activeAssistantId.value) {
    useAlert(t('INTEGRATION_SETTINGS.OPEN_AI.NO_ATHENAS_ASSISTANT'));
    return;
  }
  isSending.value = true;
  draft.value = '';
  try {
    if (selectedThreadId.value) {
      const optimistic = {
        id: `tmp-${Date.now()}`,
        role: 'user',
        content: trimmed,
        created_at: Math.floor(Date.now() / 1000),
      };
      messages.value = [...messages.value, optimistic];
      await scrollToBottom();
      const response = await AthenasAssistantsAPI.sendThreadMessage(
        selectedThreadId.value,
        trimmed
      );
      const { user_message: userMessage, assistant_message: assistantMessage } =
        response.data;
      messages.value = messages.value
        .filter(m => m.id !== optimistic.id)
        .concat([userMessage, assistantMessage].filter(Boolean));
    } else {
      isCreatingThread.value = true;
      const response = await AthenasAssistantsAPI.createThread({
        assistantId: activeAssistantId.value,
        conversationId: conversationId.value,
        initialMessage: trimmed,
      });
      const newThread = response.data;
      selectedThreadId.value = newThread.id;
      messages.value = newThread.messages || [];
      threads.value = [newThread, ...threads.value];
    }
    await scrollToBottom();
  } catch (error) {
    useAlert(error.response?.data?.error || error.message);
  } finally {
    isSending.value = false;
    isCreatingThread.value = false;
  }
};

const archiveThread = async threadId => {
  try {
    await AthenasAssistantsAPI.archiveThread(threadId);
    threads.value = threads.value.filter(item => item.id !== threadId);
    if (selectedThreadId.value === threadId) startNewThread();
  } catch (error) {
    useAlert(error.response?.data?.error || error.message);
  }
};

const handleAssistantPick = id => {
  setAssistant(id);
};

const handleKey = event => {
  if (event.key === 'Enter' && !event.shiftKey) {
    event.preventDefault();
    sendMessage();
  }
};

const formatTime = unix => {
  if (!unix) return '';
  return new Date(unix * 1000).toLocaleString(undefined, {
    hour: '2-digit',
    minute: '2-digit',
  });
};

watch(isOpen, async opened => {
  if (!opened) return;
  await fetchAssistants();
  await loadThreads();
});

watch(conversationId, async () => {
  if (!isOpen.value) return;
  startNewThread();
  await loadThreads();
});

onMounted(async () => {
  if (isOpen.value) {
    await fetchAssistants();
    await loadThreads();
  }
});
</script>

<template>
  <div
    v-if="isOpen"
    class="bg-n-surface-2 overflow-hidden flex flex-col fixed z-50 border border-n-weak shadow-2xl rounded-xl bottom-4 ltr:right-4 rtl:left-4 w-[380px] h-[600px] max-h-[80vh] max-sm:inset-4 max-sm:w-auto max-sm:h-auto max-sm:rounded-xl"
  >
    <header
      class="flex items-center justify-between gap-2 px-4 py-3 border-b border-n-weak"
    >
      <div class="flex items-center gap-2 min-w-0">
        <span
          class="inline-flex items-center justify-center size-8 rounded-full bg-n-teal-3"
        >
          <Icon icon="i-lucide-sparkles" class="text-n-teal-11 size-4" />
        </span>
        <div class="flex flex-col min-w-0">
          <span class="text-sm font-semibold text-n-slate-12 truncate">
            {{
              activeAssistant?.name ||
              t('INTEGRATION_SETTINGS.OPEN_AI.ATHENAS_COPILOT')
            }}
          </span>
          <span class="text-[11px] text-n-slate-10 leading-none">
            {{ t('INTEGRATION_SETTINGS.OPEN_AI.ATHENAS_COPILOT_SUBTITLE') }}
          </span>
        </div>
      </div>
      <Button
        ghost
        slate
        sm
        icon="i-lucide-x"
        class="!rounded-full"
        @click="closePanel"
      />
    </header>

    <section
      v-if="hasAssistants"
      class="px-4 py-2 border-b border-n-weak flex flex-wrap gap-1"
    >
      <button
        v-for="assistant in assistants"
        :key="assistant.id"
        type="button"
        class="text-[11px] px-2 py-1 rounded-full border transition-colors"
        :class="
          assistant.id === activeAssistantId
            ? 'bg-n-teal-3 border-n-teal-7 text-n-teal-12'
            : 'border-n-weak text-n-slate-11 hover:bg-n-slate-3'
        "
        @click="handleAssistantPick(assistant.id)"
      >
        {{ assistant.name }}
      </button>
    </section>

    <section
      v-if="threads.length > 0"
      class="px-4 py-2 border-b border-n-weak max-h-32 overflow-y-auto"
    >
      <div class="flex items-center justify-between mb-1">
        <span class="text-[10px] uppercase tracking-wide text-n-slate-10">
          {{ t('INTEGRATION_SETTINGS.OPEN_AI.ATHENAS_THREADS') }}
        </span>
        <button
          type="button"
          class="text-[11px] text-n-teal-11 hover:underline"
          @click="startNewThread"
        >
          {{ t('INTEGRATION_SETTINGS.OPEN_AI.ATHENAS_NEW_THREAD') }}
        </button>
      </div>
      <ul class="flex flex-col gap-0.5">
        <li
          v-for="thread in threads"
          :key="thread.id"
          class="group flex items-center gap-1"
        >
          <button
            type="button"
            class="flex-1 text-left text-xs px-2 py-1 rounded truncate"
            :class="
              thread.id === selectedThreadId
                ? 'bg-n-teal-3 text-n-teal-12'
                : 'text-n-slate-11 hover:bg-n-slate-3'
            "
            @click="selectThread(thread.id)"
          >
            {{ thread.title }}
          </button>
          <button
            type="button"
            class="opacity-0 group-hover:opacity-100 text-n-slate-9 hover:text-n-ruby-11 px-1"
            @click="archiveThread(thread.id)"
          >
            <Icon icon="i-lucide-x" class="size-3" />
          </button>
        </li>
      </ul>
    </section>

    <section
      ref="messagesContainerRef"
      class="flex-1 overflow-y-auto px-4 py-4 flex flex-col gap-3"
    >
      <div
        v-if="isLoadingMessages"
        class="flex justify-center text-n-slate-10 text-xs"
      >
        <Spinner size="small" />
      </div>
      <template v-else>
        <div
          v-if="messages.length === 0"
          class="flex flex-col items-center justify-center text-center text-n-slate-10 mt-12 px-4"
        >
          <Icon icon="i-lucide-message-circle-question" class="size-8 mb-2" />
          <p class="text-sm font-medium text-n-slate-11">
            {{ t('INTEGRATION_SETTINGS.OPEN_AI.ATHENAS_EMPTY_TITLE') }}
          </p>
          <p class="text-xs mt-1">
            {{ t('INTEGRATION_SETTINGS.OPEN_AI.ATHENAS_EMPTY_BODY') }}
          </p>
        </div>
        <div
          v-for="msg in messages"
          :key="msg.id"
          class="flex gap-2"
          :class="msg.role === 'user' ? 'flex-row-reverse' : 'flex-row'"
        >
          <div
            class="max-w-[85%] rounded-lg px-3 py-2 text-sm whitespace-pre-wrap break-words"
            :class="
              msg.role === 'user'
                ? 'bg-n-teal-9 text-white'
                : 'bg-n-slate-3 text-n-slate-12'
            "
          >
            {{ msg.content }}
            <div
              class="text-[10px] mt-1 opacity-70"
              :class="msg.role === 'user' ? 'text-white' : 'text-n-slate-10'"
            >
              {{ formatTime(msg.created_at) }}
            </div>
          </div>
        </div>
      </template>
      <div v-if="isSending" class="flex">
        <div
          class="rounded-lg px-3 py-2 bg-n-slate-3 text-n-slate-10 text-xs flex items-center gap-2"
        >
          <Spinner size="small" />
          {{ t('INTEGRATION_SETTINGS.OPEN_AI.ATHENAS_THINKING') }}
        </div>
      </div>
    </section>

    <footer class="border-t border-n-weak px-3 py-3 bg-n-surface-2">
      <div
        v-if="!hasAssistants"
        class="text-xs text-n-slate-10 text-center py-2"
      >
        {{ t('INTEGRATION_SETTINGS.OPEN_AI.NO_ATHENAS_ASSISTANT') }}
      </div>
      <div v-else class="flex items-end gap-2">
        <textarea
          v-model="draft"
          rows="2"
          class="flex-1 resize-none rounded-md bg-n-alpha-1 border border-n-weak px-2 py-1.5 text-sm text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:border-n-teal-9"
          :placeholder="
            t('INTEGRATION_SETTINGS.OPEN_AI.ATHENAS_INPUT_PLACEHOLDER')
          "
          :disabled="isSending"
          @keydown="handleKey"
        />
        <Button
          icon="i-lucide-send"
          teal
          sm
          class="!rounded-full"
          :disabled="!draft.trim() || isSending"
          @click="sendMessage"
        />
      </div>
    </footer>
  </div>
  <template v-else />
</template>
