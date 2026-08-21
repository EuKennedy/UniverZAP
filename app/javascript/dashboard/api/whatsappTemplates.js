/* global axios */
import ApiClient from './ApiClient';

/**
 * Templates de mensagem de uma caixa WhatsApp Cloud.
 *
 * Aninhado na caixa porque template pertence ao WABA daquela caixa, não à
 * conta: duas caixas da mesma conta têm catálogos diferentes.
 */
class WhatsappTemplatesAPI extends ApiClient {
  constructor() {
    super('inboxes', { accountScoped: true });
  }

  get(inboxId) {
    return axios.get(`${this.url}/${inboxId}/whatsapp_templates`);
  }

  submit(inboxId, template) {
    return axios.post(`${this.url}/${inboxId}/whatsapp_templates`, {
      template,
    });
  }

  remove(inboxId, name) {
    return axios.delete(
      `${this.url}/${inboxId}/whatsapp_templates/${encodeURIComponent(name)}`
    );
  }
}

export default new WhatsappTemplatesAPI();
