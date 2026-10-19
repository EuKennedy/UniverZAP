/* global axios */
import ApiClient from './ApiClient';

class InboxMembers extends ApiClient {
  constructor() {
    super('inbox_members', { accountScoped: true });
  }

  update({ inboxId, agentList, capacities = [] }) {
    return axios.patch(this.url, {
      inbox_id: inboxId,
      user_ids: agentList,
      capacities,
    });
  }
}

export default new InboxMembers();
