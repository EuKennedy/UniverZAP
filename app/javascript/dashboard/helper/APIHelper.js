import Auth from '../api/auth';
import { emitter } from 'shared/helpers/mitt';

// HTTP 402 ("Payment Required") is the global signal for an exhausted
// Athenas balance — the backend's BaseController#rescue_from emits it
// with a structured `{ code: 'athenas_quota_exhausted', ... }` body.
// We bubble the event via mitt so the dashboard's `AthenasCreditsModal`
// can pop up wherever the operator is. Listening is opt-in: the modal
// component subscribes on mount and unsubscribes on unmount.
const ATHENAS_QUOTA_EVENT = 'athenas-credits:open-top-up';

const parseErrorCode = error => {
  const status = error?.response?.status;
  const code = error?.response?.data?.code;
  if (status === 402 && code === 'athenas_quota_exhausted') {
    emitter.emit(ATHENAS_QUOTA_EVENT, { reason: 'quota_exhausted' });
  }
  return Promise.reject(error);
};

export default axios => {
  const { apiHost = '' } = window.chatwootConfig || {};
  const wootApi = axios.create({ baseURL: `${apiHost}/` });
  // Add Auth Headers to requests if logged in
  if (Auth.hasAuthCookie()) {
    const {
      'access-token': accessToken,
      'token-type': tokenType,
      client,
      expiry,
      uid,
    } = Auth.getAuthData();
    Object.assign(wootApi.defaults.headers.common, {
      'access-token': accessToken,
      'token-type': tokenType,
      client,
      expiry,
      uid,
    });
  }
  // Response parsing interceptor
  wootApi.interceptors.response.use(
    response => response,
    error => parseErrorCode(error)
  );
  return wootApi;
};
