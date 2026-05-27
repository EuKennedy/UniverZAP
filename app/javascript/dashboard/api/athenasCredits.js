import ApiClient from './ApiClient';

// Singleton credits endpoint — Rails `resource :credits` exposes
// /api/v1/accounts/:account_id/ai/credits (no id segment). Inherits the
// `get()` helper from ApiClient which performs `axios.get(this.url)`.
class AthenasCreditsAPI extends ApiClient {
  constructor() {
    super('ai/credits', { accountScoped: true });
  }
}

export default new AthenasCreditsAPI();
