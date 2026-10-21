import { computed, reactive, unref } from 'vue';
import ScheduledMessagesAPI from 'dashboard/api/scheduledMessages';
import { sortScheduled } from 'dashboard/helper/scheduledMessages';

// Estado compartilhado por conversa: o indicador acima do composer e o
// diálogo (aberto pelo composer ou pela ficha) enxergam a mesma lista, então
// agendar pela ficha aparece no indicador na hora.
const state = reactive({ byConversation: {} });

const setList = (conversationId, list) => {
  state.byConversation[conversationId] = sortScheduled(list);
};

const upsert = (conversationId, item) => {
  const list = (state.byConversation[conversationId] || []).filter(
    existing => existing.id !== item.id
  );
  setList(conversationId, [...list, item]);
};

export const useScheduledMessages = conversationIdRef => {
  const conversationId = computed(() => unref(conversationIdRef));

  const items = computed(
    () => state.byConversation[conversationId.value] || []
  );
  const pending = computed(() =>
    items.value.filter(item => item.status === 'scheduled')
  );

  const fetch = async () => {
    if (!conversationId.value) return;
    const { data } = await ScheduledMessagesAPI.list(conversationId.value);
    setList(conversationId.value, data.payload || []);
  };

  const create = async payload => {
    const { data } = await ScheduledMessagesAPI.create(
      conversationId.value,
      payload
    );
    upsert(conversationId.value, data);
    return data;
  };

  const update = async (id, payload) => {
    const { data } = await ScheduledMessagesAPI.update(id, payload);
    upsert(conversationId.value, data);
    return data;
  };

  const cancel = async id => {
    const { data } = await ScheduledMessagesAPI.cancel(id);
    upsert(conversationId.value, data);
    return data;
  };

  const bestTime = async () => {
    const { data } = await ScheduledMessagesAPI.bestTime(conversationId.value);
    return data;
  };

  return { items, pending, fetch, create, update, cancel, bestTime };
};
