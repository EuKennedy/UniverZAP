/* global axios */
import ApiClient from './ApiClient';

class VerticalStatusesAPI extends ApiClient {
  constructor() {
    super('vertical_statuses', { accountScoped: true });
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
