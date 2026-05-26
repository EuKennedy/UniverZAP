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

  // Subtasks reuse the regular create/update/destroy endpoints; the only
  // wrinkle is `parent_task_id` in the payload. funnel_id is required by
  // the create route, so we always thread the parent's funnel through.
  createSubtask({ parentTaskId, funnelId, funnelStageId, title }) {
    return axios.post(`${this.baseUrl()}/funnels/${funnelId}/kanban_tasks`, {
      kanban_task: {
        title,
        parent_task_id: parentTaskId,
        funnel_stage_id: funnelStageId,
      },
    });
  }

  toggleSubtask(id, completedAt) {
    return axios.patch(`${this.url}/${id}`, {
      kanban_task: { completed_at: completedAt },
    });
  }

  destroySubtask(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  fetchActivities(taskId) {
    return axios.get(`${this.url}/${taskId}/activities`);
  }

  fetchTimeEntries(taskId) {
    return axios.get(`${this.url}/${taskId}/time_entries`);
  }

  startTimer(taskId) {
    return axios.post(`${this.url}/${taskId}/time_entries/start`);
  }

  stopTimer(taskId) {
    return axios.post(`${this.url}/${taskId}/time_entries/stop`);
  }

  exportCsv(funnelId) {
    return axios.get(
      `${this.baseUrl()}/funnels/${funnelId}/kanban_tasks/export`,
      { responseType: 'blob' }
    );
  }
}

export default new KanbanTasksAPI();
