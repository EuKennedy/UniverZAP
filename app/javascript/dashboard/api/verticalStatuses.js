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

  updateSelection(titles) {
    return axios.patch(`${this.url}/selection`, { titles });
  }
}

export default new VerticalStatusesAPI();
