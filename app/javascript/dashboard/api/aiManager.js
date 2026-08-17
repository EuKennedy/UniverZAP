/* global axios */
import ApiClient from './ApiClient';

/**
 * O Gerente: quem lê as conversas do agente e propõe correções.
 *
 * Nenhum método aceita account_id. A conta sai da URL do painel, dentro de
 * ApiClient, para que uma tela aberta em uma conta não consiga aprovar
 * sugestão de outra nem mandar rodar análise que a outra vai pagar.
 */
class AiManagerAPI extends ApiClient {
  constructor() {
    super('ai/manager', { accountScoped: true });
  }

  overview() {
    return axios.get(`${this.url}/overview`);
  }

  listSuggestions({ status = 'pending' } = {}) {
    return axios.get(`${this.url}/suggestions`, { params: { status } });
  }

  approveSuggestion(id) {
    return axios.post(`${this.url}/suggestions/${id}/approve`);
  }

  // O motivo é obrigatório na tela e viaja aqui do mesmo jeito: dispensa sem
  // motivo é a fila sendo esvaziada sem ninguém aprender nada com isso.
  dismissSuggestion(id, reason) {
    return axios.post(`${this.url}/suggestions/${id}/dismiss`, { reason });
  }

  // Quanto vai custar, ANTES de custar. A tela não chama createRun sem ter
  // mostrado isto e recebido um sim.
  estimateRun() {
    return axios.get(`${this.url}/runs/estimate`);
  }

  createRun() {
    return axios.post(`${this.url}/runs`);
  }

  listChecks() {
    return axios.get(`${this.url}/checks`);
  }

  updateCheck(key, enabled) {
    return axios.patch(`${this.url}/checks/${key}`, { enabled });
  }
}

export default new AiManagerAPI();
