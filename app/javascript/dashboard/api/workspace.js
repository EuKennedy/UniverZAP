/* global axios */
import ApiClient from './ApiClient';

// UniverZAP: cover, logo, theme and vertical of the current workspace, plus
// the per-account counters shown in the account switcher.
class WorkspaceAPI extends ApiClient {
  constructor() {
    super('workspace', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  update(data) {
    return axios.patch(this.url, data);
  }

  removeAttachment(attachment) {
    return axios.delete(this.url, { params: { attachment } });
  }

  summaries() {
    return axios.get(`${this.apiVersion}/profile/workspace_summary`);
  }
}

export default new WorkspaceAPI();
