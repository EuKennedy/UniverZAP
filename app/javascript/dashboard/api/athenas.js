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

  updateTraining(assistantId, trainingId, payload) {
    return axios.patch(`${this.url}/${assistantId}/trainings/${trainingId}`, {
      ai_training: payload,
    });
  }

  deleteTraining(assistantId, trainingId) {
    return axios.delete(`${this.url}/${assistantId}/trainings/${trainingId}`);
  }

  // Measured performance for one agent, plus the last replies it sent.
  analytics(assistantId, { days = 30 } = {}) {
    return axios.get(`${this.url}/${assistantId}/analytics`, {
      params: { days },
    });
  }

  // Supervision queue: every reply the agent produced, worst first.
  listResponses(assistantId, { filter, flag, page } = {}) {
    return axios.get(`${this.url}/${assistantId}/responses`, {
      params: { filter, flag, page },
    });
  }

  // 👍 👎 ⭐ on one reply. A correction that can be applied is applied here.
  rateResponse(assistantId, responseId, payload) {
    return axios.post(
      `${this.url}/${assistantId}/responses/${responseId}/feedback`,
      { feedback: payload }
    );
  }

  applyResponseFeedback(assistantId, responseId) {
    return axios.post(
      `${this.url}/${assistantId}/responses/${responseId}/apply_feedback`
    );
  }

  // Versioned instructions and the A/B lab that gates promotion.
  listPromptVersions(assistantId) {
    return axios.get(`${this.url}/${assistantId}/prompt_versions`);
  }

  createPromptVersion(assistantId, payload) {
    return axios.post(`${this.url}/${assistantId}/prompt_versions`, payload);
  }

  promotionStats(assistantId, versionId) {
    return axios.get(
      `${this.url}/${assistantId}/prompt_versions/${versionId}/stats`
    );
  }

  replayPromptVersion(assistantId, versionId, { count } = {}) {
    return axios.post(
      `${this.url}/${assistantId}/prompt_versions/${versionId}/replay`,
      { count }
    );
  }

  promotePromptVersion(assistantId, versionId) {
    return axios.post(
      `${this.url}/${assistantId}/prompt_versions/${versionId}/promote`
    );
  }

  rollbackPromptVersion(assistantId) {
    return axios.post(`${this.url}/${assistantId}/prompt_versions/rollback`);
  }

  listComparisons(assistantId, { versionId, pending } = {}) {
    return axios.get(`${this.url}/${assistantId}/ab_comparisons`, {
      params: { version_id: versionId, pending },
    });
  }

  judgeComparison(assistantId, comparisonId, winner) {
    return axios.patch(
      `${this.url}/${assistantId}/ab_comparisons/${comparisonId}`,
      { winner }
    );
  }

  // Commercial radar: conversations that ended without a sale, plus the ROI
  // panel that turns the cost report into a business case.
  listOpportunities(assistantId, { band, status, days } = {}) {
    return axios.get(`${this.url}/${assistantId}/opportunities`, {
      params: { band, status, days },
    });
  }

  updateOpportunity(assistantId, opportunityId, payload) {
    return axios.patch(
      `${this.url}/${assistantId}/opportunities/${opportunityId}`,
      { opportunity: payload }
    );
  }

  bulkFollowUp(assistantId, { opportunityIds, message, inboxId } = {}) {
    return axios.post(
      `${this.url}/${assistantId}/opportunities/bulk_followup`,
      {
        opportunity_ids: opportunityIds,
        message,
        inbox_id: inboxId,
      }
    );
  }

  // Test sandbox: talk to the assistant as if you were a customer.
  getPlayground(assistantId) {
    return axios.get(`${this.url}/${assistantId}/playground`);
  }

  sendPlaygroundMessage(assistantId, message, { signal } = {}) {
    return axios.post(
      `${this.url}/${assistantId}/playground`,
      { message },
      { signal }
    );
  }

  resetPlayground(assistantId) {
    return axios.delete(`${this.url}/${assistantId}/playground`);
  }
}

export default new AthenasAssistantsAPI();
