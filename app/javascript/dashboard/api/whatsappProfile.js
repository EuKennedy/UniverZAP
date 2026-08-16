/* global axios */
import ApiClient from './ApiClient';

// Perfil e status do número conectado. Nenhum método aceita session_name: quem
// escolhe a sessão é o backend, a partir da inbox, para que o painel de uma
// conta não consiga operar o número de outra.
class WhatsAppProfile extends ApiClient {
  constructor() {
    super('whatsapp/profile', { accountScoped: true });
  }

  inboxes() {
    return axios.get(`${this.url}/inboxes`);
  }

  profile(inboxId) {
    return axios.get(this.url, { params: { inbox_id: inboxId } });
  }

  updateName(inboxId, name) {
    return axios.put(`${this.url}/name`, { inbox_id: inboxId, name });
  }

  updateAbout(inboxId, about) {
    return axios.put(`${this.url}/about`, { inbox_id: inboxId, about });
  }

  updatePicture(inboxId, blobId) {
    return axios.put(`${this.url}/picture`, {
      inbox_id: inboxId,
      blob_id: blobId,
    });
  }

  deletePicture(inboxId) {
    return axios.delete(`${this.url}/picture`, {
      params: { inbox_id: inboxId },
    });
  }

  publishTextStatus(inboxId, { text, backgroundColor }) {
    return axios.post(`${this.url}/status/text`, {
      inbox_id: inboxId,
      text,
      background_color: backgroundColor,
    });
  }

  publishImageStatus(inboxId, { blobId, caption }) {
    return axios.post(`${this.url}/status/image`, {
      inbox_id: inboxId,
      blob_id: blobId,
      caption,
    });
  }

  publishVideoStatus(inboxId, { blobId, backgroundColor }) {
    return axios.post(`${this.url}/status/video`, {
      inbox_id: inboxId,
      blob_id: blobId,
      background_color: backgroundColor,
    });
  }
}

export default new WhatsAppProfile();
