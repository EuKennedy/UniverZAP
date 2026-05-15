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
}

export default new KanbanTasksAPI();
