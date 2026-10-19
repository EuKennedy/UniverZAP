/* global axios */
import ApiClient from './ApiClient';

class VerticalStatusesAPI extends ApiClient {
  constructor() {
    super('vertical_statuses', { accountScoped: true });
  }

  updateSelection(titles) {
    return axios.patch(`${this.url}/selection`, { titles });
  }
}

export default new VerticalStatusesAPI();
