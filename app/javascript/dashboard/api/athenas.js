/* global axios */
import ApiClient from './ApiClient';

class AthenasAssistantsAPI extends ApiClient {
  constructor() {
    super('ai/assistants', { accountScoped: true });
  }

  duplicate(id) {
    return axios.post(`${this.url}/${id}/duplicate`);
  }

  suggest(conversationId, { signal, assistantId } = {}) {
    return axios.post(
      `${this.baseUrl()}/ai/conversations/${conversationId}/suggestion`,
      assistantId ? { ai_assistant_id: assistantId } : {},
      { signal }
    );
  }

  summarize(conversationId, { signal, assistantId } = {}) {
    return axios.post(
      `${this.baseUrl()}/ai/conversations/${conversationId}/summary`,
      assistantId ? { ai_assistant_id: assistantId } : {},
      { signal }
    );
  }

  rewrite(
    { content, operation, conversationId, assistantId },
    { signal } = {}
  ) {
    return axios.post(
      `${this.baseUrl()}/ai/rewrites`,
      {
        content,
        operation,
        conversation_display_id: conversationId,
        ai_assistant_id: assistantId,
      },
      { signal }
    );
  }

  listThreads({ conversationId } = {}) {
    return axios.get(`${this.baseUrl()}/ai/chat_threads`, {
      params: conversationId ? { conversation_id: conversationId } : {},
    });
  }

  getThread(threadId) {
    return axios.get(`${this.baseUrl()}/ai/chat_threads/${threadId}`);
  }

  createThread(
    { assistantId, conversationId, title, initialMessage },
    { signal } = {}
  ) {
    return axios.post(
      `${this.baseUrl()}/ai/chat_threads`,
      {
        ai_assistant_id: assistantId,
        conversation_id: conversationId,
        title,
        initial_message: initialMessage,
      },
      { signal }
    );
  }

  updateThread(threadId, payload) {
    return axios.patch(
      `${this.baseUrl()}/ai/chat_threads/${threadId}`,
      payload
    );
  }

  archiveThread(threadId) {
    return axios.delete(`${this.baseUrl()}/ai/chat_threads/${threadId}`);
  }

  sendThreadMessage(threadId, content, { signal } = {}) {
    return axios.post(
      `${this.baseUrl()}/ai/chat_threads/${threadId}/chat_messages`,
      { content },
      { signal }
    );
  }

  listTrainings(assistantId) {
    return axios.get(`${this.url}/${assistantId}/trainings`);
  }

  createTraining(assistantId, payload) {
    return axios.post(`${this.url}/${assistantId}/trainings`, {
      ai_training: payload,
    });
  }

  deleteTraining(assistantId, trainingId) {
    return axios.delete(`${this.url}/${assistantId}/trainings/${trainingId}`);
  }
}

export default new AthenasAssistantsAPI();
