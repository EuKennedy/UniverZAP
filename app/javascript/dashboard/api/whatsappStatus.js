/* global axios */
import ApiClient from './ApiClient';

// Status do WhatsApp: rascunhos, agendamentos, publicação em várias conexões
// e o histórico de cada entrega. As conexões vão por inbox_id; a sessão WAHA
// é sempre derivada no backend.
const toPayload = ({
  kind,
  body,
  backgroundColor,
  font,
  inboxIds,
  blobId,
  scheduledAt,
  intent,
}) => ({
  kind,
  body,
  background_color: backgroundColor,
  font,
  inbox_ids: inboxIds,
  blob_id: blobId,
  scheduled_at: scheduledAt,
  intent,
});

class WhatsAppStatus extends ApiClient {
  constructor() {
    super('whatsapp/status_posts', { accountScoped: true });
  }

  list(page = 1) {
    return axios.get(this.url, { params: { page } });
  }

  save(post) {
    return post.id
      ? axios.patch(`${this.url}/${post.id}`, toPayload(post))
      : axios.post(this.url, toPayload(post));
  }

  remove(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  publishNow(id) {
    return axios.post(`${this.url}/${id}/publish`);
  }

  retry(id) {
    return axios.post(`${this.url}/${id}/retry`);
  }

  suggest({ prompt, body, kind }) {
    return axios.post(`${this.url}/suggest`, { prompt, body, kind });
  }

  get templatesUrl() {
    return this.url.replace('status_posts', 'status_templates');
  }

  templates() {
    return axios.get(this.templatesUrl);
  }

  createTemplate({ name, body, backgroundColor, font }) {
    return axios.post(this.templatesUrl, {
      name,
      body,
      background_color: backgroundColor,
      font,
    });
  }

  removeTemplate(id) {
    return axios.delete(`${this.templatesUrl}/${id}`);
  }
}

export default new WhatsAppStatus();
