/* global axios */
import ApiClient from './ApiClient';

// UniverZAP: the name the account gives a Click-to-WhatsApp ad.
class AdNamesAPI extends ApiClient {
  constructor() {
    super('ad_names', { accountScoped: true });
  }

  save(adId, { name, campaign }) {
    return axios.patch(`${this.url}/${adId}`, { name, campaign });
  }
}

export default new AdNamesAPI();
