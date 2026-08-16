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

  // Ready-made agents per vertical.
  listTemplates() {
    return axios.get(`${this.baseUrl()}/ai/assistant_templates`);
  }

  getTemplate(key) {
    return axios.get(`${this.baseUrl()}/ai/assistant_templates/${key}`);
  }

  // What customers keep asking this agent.
  themes(assistantId, { days = 30 } = {}) {
    return axios.get(`${this.url}/${assistantId}/themes`, { params: { days } });
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

  // Integrações: the agent's own pluggable HTTP tools (Ai::CustomTool), scoped
  // to this assistant. auth_config goes up write-only and never comes back.
  listCustomTools(assistantId) {
    return axios.get(`${this.url}/${assistantId}/custom_tools`);
  }

  createCustomTool(assistantId, payload) {
    return axios.post(`${this.url}/${assistantId}/custom_tools`, {
      ai_custom_tool: payload,
    });
  }

  updateCustomTool(assistantId, toolId, payload) {
    return axios.patch(`${this.url}/${assistantId}/custom_tools/${toolId}`, {
      ai_custom_tool: payload,
    });
  }

  deleteCustomTool(assistantId, toolId) {
    return axios.delete(`${this.url}/${assistantId}/custom_tools/${toolId}`);
  }

  // Agenda: this agent's own Google grant. Per agent, so connecting the salon
  // on one and the clinic on another keeps the two calendars apart.
  calendarConnection(assistantId) {
    return axios.get(`${this.url}/${assistantId}/calendar_connection`);
  }

  // Returns the Google URL to send the browser to. Not a redirect, because a
  // 302 answering an XHR lands the operator nowhere.
  startCalendarConnection(assistantId) {
    return axios.post(`${this.url}/${assistantId}/calendar_connection`);
  }

  disconnectCalendar(assistantId) {
    return axios.delete(`${this.url}/${assistantId}/calendar_connection`);
  }

  // The other agenda. No OAuth to run: belezaki authenticates server-to-server,
  // so connecting is the operator confirming WHICH salon this agent books on,
  // and the POST proves it by reading the salon back.
  belezakiConnection(assistantId) {
    return axios.get(`${this.url}/${assistantId}/belezaki_connection`);
  }

  connectBelezaki(assistantId) {
    return axios.post(`${this.url}/${assistantId}/belezaki_connection`);
  }

  disconnectBelezaki(assistantId) {
    return axios.delete(`${this.url}/${assistantId}/belezaki_connection`);
  }

  // "Configurar negócio": the agenda name, the week and the rules travel
  // together because they are one form, and a half-saved one leaves services
  // nobody can be booked for.
  calendarSetup(assistantId) {
    return axios.get(`${this.url}/${assistantId}/calendar_setup`);
  }

  updateCalendarSetup(assistantId, payload) {
    return axios.patch(`${this.url}/${assistantId}/calendar_setup`, payload);
  }

  listCalendarServices(assistantId) {
    return axios.get(`${this.url}/${assistantId}/calendar_services`);
  }

  createCalendarService(assistantId, payload) {
    return axios.post(`${this.url}/${assistantId}/calendar_services`, {
      service: payload,
    });
  }

  updateCalendarService(assistantId, serviceId, payload) {
    return axios.patch(
      `${this.url}/${assistantId}/calendar_services/${serviceId}`,
      { service: payload }
    );
  }

  deleteCalendarService(assistantId, serviceId) {
    return axios.delete(
      `${this.url}/${assistantId}/calendar_services/${serviceId}`
    );
  }

  // Every agent of the account at once, for the Relatórios screen. The action
  // below answers for one agent and cannot answer what an account with several
  // of them asks: which one is worth the money.
  // `since`/`until` são epoch em segundos, do mesmo jeito que o resto de
  // Relatórios já fala com o backend. `days` continua aceito porque o servidor
  // ainda entende, e é o que sobra se alguém chamar isto sem intervalo.
  accountReport({ days = 30, since = null, until: untilAt = null } = {}) {
    const params = since && untilAt ? { since, until: untilAt } : { days };
    return axios.get(`${this.baseUrl()}/ai/report`, { params });
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
