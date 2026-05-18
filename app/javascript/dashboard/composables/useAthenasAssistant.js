import { ref, computed } from 'vue';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import AthenasAssistantsAPI from 'dashboard/api/athenas';

/**
 * Shared reactive state for the currently-active Athenas assistant.
 * Keyed by conversation id so that overriding the assistant in one
 * conversation does not bleed into the next.
 */
const overridesByConversation = ref({});
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

  const activeAssistantId = computed(
    () => overrideAssistantId.value || inboxAssistantId.value || null
  );

  const activeAssistant = computed(() => {
    if (!activeAssistantId.value) return null;
    return assistants.value.find(a => a.id === activeAssistantId.value) || null;
  });

  const setAssistant = id => {
    if (!conversationId.value) return;
    overridesByConversation.value = {
      ...overridesByConversation.value,
      [conversationId.value]: id,
    };
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
