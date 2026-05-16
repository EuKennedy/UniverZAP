/* global axios */
import ApiClient from '../ApiClient';

class WahaChannel extends ApiClient {
  constructor() {
    super('whatsapp/waha', { accountScoped: true });
  }

  createSession(sessionName) {
    return axios.post(`${this.baseUrl()}/whatsapp/waha/sessions`, {
      session_name: sessionName,
    });
  }

  showSession(name) {
    return axios.get(
      `${this.baseUrl()}/whatsapp/waha/sessions/${encodeURIComponent(name)}`
    );
  }

  sessionQr(name) {
    return axios.get(
      `${this.baseUrl()}/whatsapp/waha/sessions/${encodeURIComponent(name)}/qr`
    );
  }

  connectExisting(name) {
    return axios.post(
      `${this.baseUrl()}/whatsapp/waha/sessions/${encodeURIComponent(name)}/connect`
    );
  }

  logoutSession(name) {
    return axios.post(
      `${this.baseUrl()}/whatsapp/waha/sessions/${encodeURIComponent(name)}/logout`
    );
  }
}

export default new WahaChannel();
