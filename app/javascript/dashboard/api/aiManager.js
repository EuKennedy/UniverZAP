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

  // O moderador de conversas. Chamadas separadas de propósito: `listFindings`
  // é de graça e roda a cada mudança de filtro, `createScan` gasta e roda
  // quando alguém clica. Misturá-las num método só seria a maneira mais fácil
  // de um filtro passar a custar dinheiro sem ninguém perceber.
  listFindings({ days, author, caseKey } = {}) {
    return axios.get(`${this.url}/conversations`, {
      params: { days, author, case_key: caseKey },
    });
  }

  estimateScan(hours) {
    return axios.get(`${this.url}/conversations/estimate`, {
      params: { hours },
    });
  }

  createScan(hours) {
    return axios.post(`${this.url}/conversations/scans`, { hours });
  }

  // Consultada enquanto a leitura roda. A varredura é assíncrona porque chama
  // modelo uma vez por conversa e leva minutos.
  getScan(id) {
    return axios.get(`${this.url}/conversations/scans/${id}`);
  }
}

export default new AiManagerAPI();
