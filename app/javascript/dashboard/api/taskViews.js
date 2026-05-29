/* global axios */
import ApiClient from './ApiClient';

// Saved task-views API. Mirrors the Tasks API conventions:
// account-scoped + camelCase wrappers around snake_case payloads.
class TaskViewsAPI extends ApiClient {
  constructor() {
    super('task_views', { accountScoped: true });
  }

  create(payload) {
    return axios.post(this.url, { task_view: payload });
  }

  update(id, payload) {
    return axios.patch(`${this.url}/${id}`, { task_view: payload });
  }

  setDefault(id) {
    return axios.post(`${this.url}/${id}/set_default`);
  }
}

export default new TaskViewsAPI();
