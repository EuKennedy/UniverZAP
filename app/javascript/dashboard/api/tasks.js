/* global axios */
import ApiClient from './ApiClient';

// Dashboard-side Tasks API client. Backed by the v1 controller mounted at
// `/api/v1/accounts/:account_id/tasks`. Listing accepts the same filter
// vocabulary as `Tasks::Finder` (scope/status/urgency/assignee/due_before/q).
//
// The realtime channel surfaces full task payloads via `push_event_data`,
// so every mutating endpoint returns the same shape — the store can blindly
// upsert the response without a second fetch.
class TasksAPI extends ApiClient {
  constructor() {
    super('tasks', { accountScoped: true });
  }

  fetch(params = {}) {
    return axios.get(this.url, { params });
  }

  create(payload) {
    return axios.post(this.url, { task: payload });
  }

  update(id, payload) {
    return axios.patch(`${this.url}/${id}`, { task: payload });
  }

  assign(id, userId) {
    return axios.post(`${this.url}/${id}/assign`, { user_id: userId });
  }

  unassign(id, userId) {
    return axios.delete(`${this.url}/${id}/assignees/${userId}`);
  }

  complete(id) {
    return axios.post(`${this.url}/${id}/complete`);
  }

  addComment(id, body) {
    return axios.post(`${this.url}/${id}/comments`, { body });
  }

  fetchActivities(id, params = {}) {
    return axios.get(`${this.url}/${id}/activities`, { params });
  }
}

export default new TasksAPI();
