/* global axios */
import ApiClient from './ApiClient';

class ChatflowsAPI extends ApiClient {
  constructor() {
    super('chatflows', { accountScoped: true });
  }

  create(name) {
    return axios.post(this.url, { chatflow: { name } });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, { chatflow: data });
  }

  activate(id) {
    return axios.post(`${this.url}/${id}/activate`);
  }

  archive(id) {
    return axios.post(`${this.url}/${id}/archive`);
  }

  test(id, phone) {
    return axios.post(`${this.url}/${id}/test`, { phone });
  }

  stopTest(id) {
    return axios.post(`${this.url}/${id}/stop_test`);
  }

  // --- graph: nodes ------------------------------------------------------

  createNode(chatflowId, node) {
    return axios.post(`${this.url}/${chatflowId}/nodes`, {
      chatflow_node: node,
    });
  }

  updateNode(chatflowId, nodeId, node) {
    return axios.patch(`${this.url}/${chatflowId}/nodes/${nodeId}`, {
      chatflow_node: node,
    });
  }

  deleteNode(chatflowId, nodeId) {
    return axios.delete(`${this.url}/${chatflowId}/nodes/${nodeId}`);
  }

  // --- graph: edges ------------------------------------------------------

  createEdge(chatflowId, edge) {
    return axios.post(`${this.url}/${chatflowId}/edges`, {
      chatflow_edge: edge,
    });
  }

  deleteEdge(chatflowId, edgeId) {
    return axios.delete(`${this.url}/${chatflowId}/edges/${edgeId}`);
  }
}

export default new ChatflowsAPI();
