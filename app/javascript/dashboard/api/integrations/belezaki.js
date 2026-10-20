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

  getCatalog() {
    return axios.get(`${this.url}/catalog`);
  }

  syncCatalog() {
    return axios.post(`${this.url}/sync_catalog`);
  }
}

export default new BelezakiAPI();
