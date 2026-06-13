/* global axios */
import ApiClient from './ApiClient';

class BroadcastsAPI extends ApiClient {
  constructor() {
    super('broadcasts', { accountScoped: true });
  }

  create(data) {
    return axios.post(this.url, { broadcast: data });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, { broadcast: data });
  }

  launch(id) {
    return axios.post(`${this.url}/${id}/launch`);
  }

  pause(id) {
    return axios.post(`${this.url}/${id}/pause`);
  }

  audiencePreview(id) {
    return axios.get(`${this.url}/${id}/audience_preview`);
  }
}

export default new BroadcastsAPI();
