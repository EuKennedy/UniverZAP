/* global axios */
import ApiClient from './ApiClient';

class VerticalStatusesAPI extends ApiClient {
  constructor() {
    super('vertical_statuses', { accountScoped: true });
  }

  // An agent's own bar: the statuses for exactly these titles, in this order.
  getFor(titles) {
    return axios.get(this.url, { params: { titles } });
  }

  getCatalog() {
    return axios.get(`${this.url}/catalog`);
  }

  // Every stage of the account's vertical, closing ones included.
  fetchAll() {
    return axios.get(this.url, { params: { scope: 'all' } });
  }

  updateSelection(titles) {
    return axios.patch(`${this.url}/selection`, { titles });
  }
}

export default new VerticalStatusesAPI();
