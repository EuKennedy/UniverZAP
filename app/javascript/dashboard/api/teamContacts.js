/* global axios */
import ApiClient from './ApiClient';

// UniverZAP: the contacts in the Equipe tab.
class TeamContactsAPI extends ApiClient {
  constructor() {
    super('team_contacts', { accountScoped: true });
  }

  add(contactId) {
    return axios.post(this.url, { contact_id: contactId });
  }

  remove(contactId) {
    return axios.delete(`${this.url}/${contactId}`);
  }
}

export default new TeamContactsAPI();
