/* global axios */
import ApiClient from './ApiClient';

// Listas de distribuição: fotos de contatos (grupo do WhatsApp, CSV, manual
// ou filtro) que viram público de disparo.
class ContactListsAPI extends ApiClient {
  constructor() {
    super('contact_lists', { accountScoped: true });
  }

  create(data) {
    return axios.post(this.url, { contact_list: data });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, { contact_list: data });
  }

  stats() {
    return axios.get(`${this.url}/stats`);
  }

  members(id, { page = 1, filter = 'all', q = '' } = {}) {
    return axios.get(`${this.url}/${id}/members`, {
      params: { page, filter, q },
    });
  }

  addMembers(id, contactIds) {
    return axios.post(`${this.url}/${id}/add_members`, {
      contact_ids: contactIds,
    });
  }

  removeMembers(id, memberIds) {
    return axios.post(`${this.url}/${id}/remove_members`, {
      member_ids: memberIds,
    });
  }

  importCsv(id, { content, cold }) {
    return axios.post(`${this.url}/${id}/import_csv`, { content, cold });
  }

  refresh(id) {
    return axios.post(`${this.url}/${id}/refresh`);
  }

  deduplicate(id) {
    return axios.post(`${this.url}/${id}/deduplicate`);
  }

  exportCsv(id) {
    return axios.get(`${this.url}/${id}/export`, { responseType: 'blob' });
  }

  merge({ listIds, name }) {
    return axios.post(`${this.url}/merge`, { list_ids: listIds, name });
  }

  groups() {
    return axios.get(`${this.url}/groups`);
  }

  extractGroup(conversationId) {
    return axios.post(`${this.url}/extract_group`, {
      conversation_id: conversationId,
    });
  }
}

export default new ContactListsAPI();
