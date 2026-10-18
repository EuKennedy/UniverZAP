import ApiClient from './ApiClient';

class VerticalStatusesAPI extends ApiClient {
  constructor() {
    super('vertical_statuses', { accountScoped: true });
  }
}

export default new VerticalStatusesAPI();
