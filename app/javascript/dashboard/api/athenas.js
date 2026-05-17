/* global axios */
import ApiClient from './ApiClient';

class AthenasAssistantsAPI extends ApiClient {
  constructor() {
    super('ai/assistants', { accountScoped: true });
  }

  duplicate(id) {
    return axios.post(`${this.url}/${id}/duplicate`);
  }

  suggest(conversationId) {
    return axios.post(
      `${this.baseUrl()}/ai/conversations/${conversationId}/suggestion`
    );
  }

  listTrainings(assistantId) {
    return axios.get(`${this.url}/${assistantId}/trainings`);
  }

  createTraining(assistantId, payload) {
    return axios.post(`${this.url}/${assistantId}/trainings`, {
      ai_training: payload,
    });
  }

  deleteTraining(assistantId, trainingId) {
    return axios.delete(`${this.url}/${assistantId}/trainings/${trainingId}`);
  }
}

export default new AthenasAssistantsAPI();
