/* global axios */
import ApiClient from './ApiClient';

class SaleRecordsAPI extends ApiClient {
  constructor() {
    super('sale_records', { accountScoped: true });
  }

  create(contactId, amount, options = {}) {
    return axios.post(this.url, { contact_id: contactId, amount, ...options });
  }

  forContact(contactId) {
    return axios.get(this.url, { params: { contact_id: contactId } });
  }
}

export default new SaleRecordsAPI();
