import { ref, computed } from 'vue';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import AthenasAssistantsAPI from 'dashboard/api/athenas';

/**
 * Shared reactive state for the currently-active Athenas assistant.
 * Keyed by conversation id so that overriding the assistant in one
 * conversation does not bleed into the next. A `globalDefault` slot
 * captures picks made before any conversation is selected (e.g. when
 * the agent opens the copilot panel directly from the sidebar). The
 * default is persisted in localStorage so reps don't have to re-pick
 * Élisa after a page reload.
 */
const GLOBAL_DEFAULT_KEY = 'univerzap.athenas.default_assistant_id';
const overridesByConversation = ref({});
const globalDefaultAssistantId = ref(
  (() => {
    try {
      const raw = window.localStorage.getItem(GLOBAL_DEFAULT_KEY);
      return raw ? Number(raw) || raw : null;
    } catch (_) {
      return null;
    }
  })()
);
const assistants = ref([]);
const isLoadingAssistants = ref(false);
const lastFetchedAccountId = ref(null);

export function useAthenasAssistant() {
  const store = useStore();
  const currentChat = useMapGetter('getSelectedChat');
  const currentAccountId = useMapGetter('getCurrentAccountId');

  const conversationId = computed(() => currentChat.value?.id ?? null);

  const inboxAssistantId = computed(() => {
    const inboxId = currentChat.value?.inbox_id;
    if (!inboxId) return null;
    const inbox = store.getters['inboxes/getInbox'](inboxId);
    return inbox?.ai_assistant_id || null;
  });

  const overrideAssistantId = computed(() => {
    if (!conversationId.value) return null;
    return overridesByConversation.value[conversationId.value] || null;
  });

  // Resolution order: per-conversation override → inbox default → user's
  // last manual pick (persisted) → first active assistant in the account.
  // The last-resort fallback lets the chip in the copilot panel work even
  // when no inbox / conversation has been bound to an assistant yet —
  // before this fix, picking Élisa from the chip was a silent no-op when
  // the panel was opened outside a conversation.
  const activeAssistantId = computed(
    () =>
      overrideAssistantId.value ||
      inboxAssistantId.value ||
      globalDefaultAssistantId.value ||
      assistants.value[0]?.id ||
      null
  );

  const activeAssistant = computed(() => {
    if (!activeAssistantId.value) return null;
    return assistants.value.find(a => a.id === activeAssistantId.value) || null;
  });

  const setAssistant = id => {
    // Always remember the pick as the global default so repeated opens of
    // the panel land on the same assistant. When a conversation is active
    // we also record a per-conversation override so swapping in another
    // assistant for a single chat doesn't pollute the default.
    globalDefaultAssistantId.value = id;
    try {
      window.localStorage.setItem(GLOBAL_DEFAULT_KEY, String(id));
    } catch (_) {
      /* localStorage unavailable — fall back to in-memory only. */
    }

    if (conversationId.value) {
      overridesByConversation.value = {
        ...overridesByConversation.value,
        [conversationId.value]: id,
      };
    }
  };

  const clearOverride = () => {
    if (!conversationId.value) return;
    const next = { ...overridesByConversation.value };
    delete next[conversationId.value];
    overridesByConversation.value = next;
  };

  const fetchAssistants = async ({ force = false } = {}) => {
    const accountId = currentAccountId.value;
    if (!accountId) return assistants.value;
    if (
      !force &&
      lastFetchedAccountId.value === accountId &&
      assistants.value.length
    ) {
      return assistants.value;
    }
    isLoadingAssistants.value = true;
    try {
      const response = await AthenasAssistantsAPI.get();
      const records = Array.isArray(response.data?.payload)
        ? response.data.payload
        : response.data || [];
      assistants.value = records.filter(a => a.active !== false);
      lastFetchedAccountId.value = accountId;
    } finally {
      isLoadingAssistants.value = false;
    }
    return assistants.value;
  };

  return {
    assistants,
    isLoadingAssistants,
    activeAssistantId,
    activeAssistant,
    inboxAssistantId,
    overrideAssistantId,
    fetchAssistants,
    setAssistant,
    clearOverride,
  };
}
