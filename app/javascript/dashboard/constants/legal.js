// Single source of truth for legal versions on the frontend. MUST mirror
// lib/legal/versions.rb on the backend — bump both together when a term
// changes. The banners use these values to decide if re-accept is needed.
export const LEGAL_VERSIONS = Object.freeze({
  terms: '2026-05-26',
  privacy: '2026-05-26',
});

// localStorage keys
export const COOKIE_CONSENT_STORAGE_KEY = 'univerzap_cookie_consent';
export const COOKIE_CONSENT_VERSION = '2026-05-26';
