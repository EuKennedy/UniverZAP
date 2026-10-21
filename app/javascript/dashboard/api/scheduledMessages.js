/* global axios */
import ApiClient from './ApiClient';

// Mensagens agendadas de uma conversa (composer e ficha da cliente).
class ScheduledMessagesAPI extends ApiClient {
  constructor() {
    super('scheduled_messages', { accountScoped: true });
  }

  list(conversationId) {
    return axios.get(this.url, { params: { conversation_id: conversationId } });
  }

  create(conversationId, data) {
    return axios.post(this.url, {
      conversation_id: conversationId,
      scheduled_message: data,
    });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, { scheduled_message: data });
  }

  cancel(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  bestTime(conversationId) {
    return axios.get(`${this.url}/best_time`, {
      params: { conversation_id: conversationId },
    });
  }
}

export default new ScheduledMessagesAPI();
