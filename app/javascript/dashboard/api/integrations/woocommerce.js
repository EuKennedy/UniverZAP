/* global axios */

import ApiClient from '../ApiClient';

// UniverZAP: the WooCommerce store of an e-commerce workspace.
class WoocommerceAPI extends ApiClient {
  constructor() {
    super('integrations/woocommerce', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  connect(data) {
    return axios.post(this.url, data);
  }

  sync() {
    return axios.post(`${this.url}/sync`);
  }

  disconnect() {
    return axios.delete(this.url);
  }

  getOrders(contactId) {
    return axios.get(`${this.url}/orders`, {
      params: { contact_id: contactId },
    });
  }
}

export default new WoocommerceAPI();
