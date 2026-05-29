/* global axios */
import ApiClient from './ApiClient';

// Dashboard-side team-chat API. Channels live at
// `/api/v1/accounts/:id/team_chat_channels`; messages are nested under
// each channel. Real-time delivery rides AccountTeamChatChannel — every
// mutating endpoint returns the same `push_event_data` shape the websocket
// emits, so the store can upsert the response without a refetch.
class TeamChatAPI extends ApiClient {
  constructor() {
    super('team_chat_channels', { accountScoped: true });
  }

  // --- channels -----------------------------------------------------------
  channels() {
    return axios.get(this.url);
  }

  createChannel(payload) {
    return axios.post(this.url, { team_chat_channel: payload });
  }

  updateChannel(id, payload) {
    return axios.patch(`${this.url}/${id}`, { team_chat_channel: payload });
  }

  archiveChannel(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  // --- messages -----------------------------------------------------------
  // `beforeId` walks back through history for infinite scroll: pass the id
  // of the oldest loaded message to fetch the page before it.
  messages(channelId, { beforeId } = {}) {
    const params = {};
    if (beforeId) params.before_id = beforeId;
    return axios.get(`${this.url}/${channelId}/messages`, { params });
  }

  sendMessage(channelId, content) {
    return axios.post(`${this.url}/${channelId}/messages`, {
      team_chat_message: { content },
    });
  }

  updateMessage(channelId, messageId, content) {
    return axios.patch(`${this.url}/${channelId}/messages/${messageId}`, {
      team_chat_message: { content },
    });
  }

  deleteMessage(channelId, messageId) {
    return axios.delete(`${this.url}/${channelId}/messages/${messageId}`);
  }
}

export default new TeamChatAPI();
