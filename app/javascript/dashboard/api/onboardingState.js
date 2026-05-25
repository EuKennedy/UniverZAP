import ApiClient from './ApiClient';

// Singleton resource — Rails `resource :onboarding_state` exposes /onboarding_state (no id).
// Inherits `get()` from ApiClient which performs `axios.get(this.url)`.
class OnboardingStateAPI extends ApiClient {
  constructor() {
    super('onboarding_state', { accountScoped: true });
  }
}

export default new OnboardingStateAPI();
