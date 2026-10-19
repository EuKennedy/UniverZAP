/* global axios */

import ApiClient from '../ApiClient';

class BelezakiAPI extends ApiClient {
  constructor() {
    super('integrations/belezaki', { accountScoped: true });
  }

  getCustomer(contactId) {
    return axios.get(`${this.url}/customer`, {
      params: { contact_id: contactId },
    });
  }
}

export default new BelezakiAPI();
