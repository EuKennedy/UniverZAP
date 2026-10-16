/* global axios */
import ApiClient from './ApiClient';

class InboxGroupsAPI extends ApiClient {
  constructor() {
    super('inbox_groups', { accountScoped: true });
  }

  create(payload) {
    return axios.post(this.url, { inbox_group: payload });
  }

  update(id, payload) {
    return axios.patch(`${this.url}/${id}`, { inbox_group: payload });
  }
}

export default new InboxGroupsAPI();
