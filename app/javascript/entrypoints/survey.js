import { createApp } from 'vue';
import { createI18n } from 'vue-i18n';
import store from '../survey/store';
import i18nMessages from '../survey/i18n';
import App from '../survey/App.vue';

// Pick the best initial locale before the survey API responds. The page
// is public so we can't rely on the account locale; sniff Accept-Language
// via `navigator.languages` and fall back through:
//   1. exact match  (pt_BR)
//   2. underscore form of "pt-BR" → "pt_BR"
//   3. region-stripped match (pt)
//   4. English
// Once the CSAT survey API replies the runtime swaps locale to the
// account's preference (Response.vue#setLocale), so this is just to keep
// the very first render localized instead of flashing English.
const resolveInitialLocale = messages => {
  if (typeof window === 'undefined' || !window.navigator) return 'en';
  const supported = new Set(Object.keys(messages));
  const candidates = (window.navigator.languages || [window.navigator.language])
    .filter(Boolean)
    .flatMap(raw => {
      const tag = raw.replace('-', '_');
      const base = tag.split('_')[0];
      return [tag, base];
    });
  return candidates.find(code => supported.has(code)) || 'en';
};

const app = createApp(App);
const i18n = createI18n({
  locale: resolveInitialLocale(i18nMessages),
  fallbackLocale: 'en',
  messages: i18nMessages,
});

app.use(i18n);
app.use(store);

window.onload = () => {
  window.WOOT_SURVEY = app.mount('#app');
};
