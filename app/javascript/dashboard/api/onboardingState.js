/* global axios */
import ApiClient from './ApiClient';

// Singleton resource — Rails `resource :onboarding_state` exposes
// /onboarding_state (no id). Inherits `get()` from ApiClient which performs
// `axios.get(this.url)`. The custom `patch()` writes the whitelisted
// onboarding keys into Account#custom_attributes server-side so progress
// survives a refresh and a backend recompute of `completed`/`regressed_steps`.
class OnboardingStateAPI extends ApiClient {
  constructor() {
    super('onboarding_state', { accountScoped: true });
  }

  patch(customAttributes) {
    return axios.patch(this.url, {
      custom_attributes: customAttributes,
    });
  }
}

export default new OnboardingStateAPI();
