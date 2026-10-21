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

  // `refresh` makes the backend sync from Meta before listing, so a template
  // approved minutes ago shows up without waiting for the scheduled sync.
  templates(inboxId, { refresh = false } = {}) {
    return axios.get(`${this.url}/templates`, {
      params: { inbox_id: inboxId, refresh },
    });
  }

  recipients(id, { filter = 'all', q = '' } = {}) {
    return axios.get(`${this.url}/${id}/recipients`, { params: { filter, q } });
  }

  // CSV de todos os destinatários do filtro atual (não só os 200 da tela).
  exportRecipients(id, { filter = 'all', q = '' } = {}) {
    return axios.get(`${this.url}/${id}/export`, {
      params: { filter, q },
      responseType: 'blob',
    });
  }

  stats() {
    return axios.get(`${this.url}/stats`);
  }

  duplicate(id) {
    return axios.post(`${this.url}/${id}/duplicate`);
  }

  // 2–3 versões do texto pela IA da conta (o operador revisa antes de salvar).
  variations(text) {
    return axios.post(`${this.url}/variations`, { text });
  }
}

export default new BroadcastsAPI();
