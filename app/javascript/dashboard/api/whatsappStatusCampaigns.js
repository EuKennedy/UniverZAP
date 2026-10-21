/* global axios */
import ApiClient from './ApiClient';

// Pastas e campanhas de status. Os passos vão junto com a campanha, na mesma
// requisição, para o backend salvar tudo ou nada.
const stepPayload = step => ({
  id: step.id,
  kind: step.kind,
  body: step.body,
  background_color: step.backgroundColor,
  font: step.font,
  day_offset: step.dayOffset,
  time_of_day: step.timeOfDay,
  repost_count: step.repostCount,
  repost_interval_hours: step.repostIntervalHours,
  blob_id: step.blobId,
});

const campaignPayload = campaign => ({
  name: campaign.name,
  description: campaign.description,
  color: campaign.color,
  folder_id: campaign.folderId || null,
  inbox_ids: campaign.inboxIds,
  starts_on: campaign.startsOn || null,
  ends_on: campaign.endsOn || null,
  cycle_days: campaign.cycleDays,
  time_zone: campaign.timeZone,
  steps: campaign.steps?.map(stepPayload),
});

class WhatsAppStatusCampaigns extends ApiClient {
  constructor() {
    super('whatsapp/status_campaigns', { accountScoped: true });
  }

  get foldersUrl() {
    return this.url.replace('status_campaigns', 'status_folders');
  }

  list({ folderId, status, q } = {}) {
    return axios.get(this.url, {
      params: {
        folder_id: folderId || undefined,
        status: status || undefined,
        q: q || undefined,
      },
    });
  }

  find(id) {
    return axios.get(`${this.url}/${id}`);
  }

  save(campaign) {
    return campaign.id
      ? axios.patch(`${this.url}/${campaign.id}`, campaignPayload(campaign))
      : axios.post(this.url, campaignPayload(campaign));
  }

  remove(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  activate(id) {
    return axios.post(`${this.url}/${id}/activate`);
  }

  pause(id) {
    return axios.post(`${this.url}/${id}/pause`);
  }

  preview(id) {
    return axios.get(`${this.url}/${id}/preview`);
  }

  folders() {
    return axios.get(this.foldersUrl);
  }

  createFolder({ name, color }) {
    return axios.post(this.foldersUrl, { name, color });
  }

  updateFolder(id, { name, color }) {
    return axios.patch(`${this.foldersUrl}/${id}`, { name, color });
  }

  removeFolder(id) {
    return axios.delete(`${this.foldersUrl}/${id}`);
  }
}

export default new WhatsAppStatusCampaigns();
