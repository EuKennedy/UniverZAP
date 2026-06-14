/* global axios */
import ApiClient from './ApiClient';

class SalesGoalsAPI extends ApiClient {
  constructor() {
    super('sales_goals', { accountScoped: true });
  }

  create(data) {
    return axios.post(this.url, { sales_goal: data });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, { sales_goal: data });
  }
}

export default new SalesGoalsAPI();
