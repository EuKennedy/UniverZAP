/* global axios */
import ApiClient from './ApiClient';

/**
 * The installation-wide sidebar layout.
 *
 * Write only, and not account scoped: one layout serves every tenant, and it
 * arrives with the page in `window.globalConfig` — so there is nothing to fetch.
 */
class SidebarLayoutAPI extends ApiClient {
  constructor() {
    super('sidebar_layout', { accountScoped: false });
  }

  update(layout) {
    return axios.put(`${this.url}`, { layout });
  }
}

export default new SidebarLayoutAPI();
