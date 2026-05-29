/* global axios */
import ApiClient from './ApiClient';

// Thin client over `/api/v1/accounts/:id/kanban_automations`. The backend
// supports optional `funnel_id` / `event_name` / `active` filters on
// list, and exposes member `test` (dry-run) + `run` (force-execute)
// endpoints used by the rule editor. Payload shape matches the model's
// `push_event_data` so the UI never has to translate between camel/snake.
class KanbanAutomationsAPI extends ApiClient {
  constructor() {
    super('kanban_automations', { accountScoped: true });
  }

  // GET /kanban_automations?funnel_id&event_name&active
  list({ funnelId, eventName, active } = {}) {
    const params = {};
    if (funnelId !== undefined && funnelId !== null)
      params.funnel_id = funnelId;
    if (eventName) params.event_name = eventName;
    if (active !== undefined) params.active = active;
    return axios.get(this.url, { params });
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  create(payload) {
    return axios.post(this.url, { kanban_automation: payload });
  }

  update(id, payload) {
    return axios.patch(`${this.url}/${id}`, { kanban_automation: payload });
  }

  destroy(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  // POST /kanban_automations/:id/test
  // Dry-run the rule against a single task. Used by the "Test rule"
  // button in the editor footer.
  test(id, { taskId }) {
    return axios.post(`${this.url}/${id}/test`, { task_id: taskId });
  }

  // POST /kanban_automations/:id/run
  // Force-execute the rule against a single task NOW. Hidden behind a
  // confirmation prompt because this WILL emit side effects.
  run(id, { taskId }) {
    return axios.post(`${this.url}/${id}/run`, { task_id: taskId });
  }
}

export default new KanbanAutomationsAPI();
