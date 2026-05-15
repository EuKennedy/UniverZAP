/* global axios */
import ApiClient from './ApiClient';

class FunnelsAPI extends ApiClient {
  constructor() {
    super('funnels', { accountScoped: true });
  }

  create(data) {
    return axios.post(this.url, { funnel: data });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, { funnel: data });
  }

  fetchStages(funnelId) {
    return axios.get(`${this.url}/${funnelId}/funnel_stages`);
  }

  createStage(funnelId, payload) {
    return axios.post(`${this.url}/${funnelId}/funnel_stages`, {
      funnel_stage: payload,
    });
  }

  updateStage(funnelId, stageId, payload) {
    return axios.patch(`${this.url}/${funnelId}/funnel_stages/${stageId}`, {
      funnel_stage: payload,
    });
  }

  deleteStage(funnelId, stageId) {
    return axios.delete(`${this.url}/${funnelId}/funnel_stages/${stageId}`);
  }

  reorderStages(funnelId, orderedStageIds) {
    return axios.post(`${this.url}/${funnelId}/funnel_stages/reorder`, {
      ordered_ids: orderedStageIds,
    });
  }

  fetchTasks(funnelId) {
    return axios.get(`${this.url}/${funnelId}/kanban_tasks`);
  }

  createTask(funnelId, payload) {
    return axios.post(`${this.url}/${funnelId}/kanban_tasks`, {
      kanban_task: payload,
    });
  }
}

export default new FunnelsAPI();
