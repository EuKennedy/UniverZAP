/* global axios */
import ApiClient from './ApiClient';

/**
 * Formulários nativos do WhatsApp (Flows).
 *
 * Na conta, e não na caixa, porque o builder do Chatflow lista todos de uma
 * vez; cada Flow carrega o `inbox_id` da caixa (WABA) a que pertence.
 */
class WhatsappFlowsAPI extends ApiClient {
  constructor() {
    super('whatsapp_flows', { accountScoped: true });
  }

  list(inboxId) {
    return axios.get(this.url, {
      params: inboxId ? { inbox_id: inboxId } : {},
    });
  }

  templates() {
    return axios.get(`${this.url}/templates`);
  }

  create(whatsappFlow) {
    return axios.post(this.url, { whatsapp_flow: whatsappFlow });
  }

  update(id, whatsappFlow) {
    return axios.patch(`${this.url}/${id}`, { whatsapp_flow: whatsappFlow });
  }

  publish(id) {
    return axios.post(`${this.url}/${id}/publish`);
  }

  deprecate(id) {
    return axios.post(`${this.url}/${id}/deprecate`);
  }

  sync(id) {
    return axios.post(`${this.url}/${id}/sync`);
  }

  remove(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new WhatsappFlowsAPI();
