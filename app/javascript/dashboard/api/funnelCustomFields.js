/* global axios */
import ApiClient from './ApiClient';

class FunnelCustomFieldsAPI extends ApiClient {
  constructor() {
    // Mount under accounts/:id/funnel_custom_fields purely so ApiClient gives
    // us baseUrl(); the real routes are nested under each funnel and built
    // ad-hoc below.
    super('funnel_custom_fields', { accountScoped: true });
  }

  list(funnelId) {
    return axios.get(
      `${this.baseUrl()}/funnels/${funnelId}/funnel_custom_fields`
    );
  }

  create(funnelId, payload) {
    return axios.post(
      `${this.baseUrl()}/funnels/${funnelId}/funnel_custom_fields`,
      { funnel_custom_field: payload }
    );
  }

  update(funnelId, id, payload) {
    return axios.patch(
      `${this.baseUrl()}/funnels/${funnelId}/funnel_custom_fields/${id}`,
      { funnel_custom_field: payload }
    );
  }

  destroy(funnelId, id) {
    return axios.delete(
      `${this.baseUrl()}/funnels/${funnelId}/funnel_custom_fields/${id}`
    );
  }

  reorder(funnelId, orderedIds) {
    return axios.post(
      `${this.baseUrl()}/funnels/${funnelId}/funnel_custom_fields/reorder`,
      { ordered_ids: orderedIds }
    );
  }
}

export default new FunnelCustomFieldsAPI();
