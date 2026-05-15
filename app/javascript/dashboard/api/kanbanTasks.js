/* global axios */
import ApiClient from './ApiClient';

class KanbanTasksAPI extends ApiClient {
  constructor() {
    super('kanban_tasks', { accountScoped: true });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, { kanban_task: data });
  }

  move(id, { funnel_stage_id: funnelStageId, position }) {
    return axios.post(`${this.url}/${id}/move`, {
      funnel_stage_id: funnelStageId,
      position,
    });
  }

  attachConversation(id, conversationId) {
    return axios.post(`${this.url}/${id}/attach_conversation`, {
      conversation_id: conversationId,
    });
  }

  detachConversation(id, conversationId) {
    return axios.delete(`${this.url}/${id}/detach_conversation`, {
      data: { conversation_id: conversationId },
    });
  }

  fetchByConversation(conversationId) {
    return axios.get(
      `${this.baseUrl()}/conversations/${conversationId}/kanban_tasks`
    );
  }
}

export default new KanbanTasksAPI();
