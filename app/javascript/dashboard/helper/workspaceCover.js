// UniverZAP: cover themes of a workspace. `n-blue` is the brand green in
// this theme, so the blues come from `n-iris`. The keys mirror
// AccountWorkspaceCover::COVER_THEMES on the backend; the classes are written
// out in full so Tailwind keeps them in the build.
export const COVER_THEMES = {
  brand: 'bg-brand-gradient',
  aurora: 'bg-gradient-to-br from-n-teal-8 via-n-teal-9 to-n-iris-9',
  sunset: 'bg-gradient-to-br from-n-amber-9 via-n-ruby-9 to-n-violet-9',
  ocean: 'bg-gradient-to-br from-n-iris-8 via-n-iris-9 to-n-violet-10',
  berry: 'bg-gradient-to-br from-n-ruby-9 via-n-ruby-10 to-n-violet-10',
  ember: 'bg-gradient-to-br from-n-amber-8 via-n-amber-9 to-n-ruby-9',
  orchid: 'bg-gradient-to-br from-n-violet-8 via-n-violet-9 to-n-ruby-9',
  graphite: 'bg-gradient-to-br from-n-slate-11 via-n-slate-10 to-n-slate-8',
  solid_teal: 'bg-n-teal-9',
  solid_iris: 'bg-n-iris-9',
  solid_ruby: 'bg-n-ruby-9',
  solid_amber: 'bg-n-amber-9',
  solid_violet: 'bg-n-violet-9',
  solid_slate: 'bg-n-slate-11',
};

export const GRADIENT_THEMES = Object.keys(COVER_THEMES).filter(
  key => !key.startsWith('solid_')
);
export const SOLID_THEMES = Object.keys(COVER_THEMES).filter(key =>
  key.startsWith('solid_')
);

// Graphite reads as "nothing chosen", so the automatic pick skips it.
const AUTO_THEMES = GRADIENT_THEMES.filter(key => key !== 'graphite');

// FNV-1a: short names that differ by a letter still land on different themes.
export const autoCoverTheme = (name = '') => {
  const hash = [...name.toLowerCase()].reduce(
    // eslint-disable-next-line no-bitwise
    (acc, char) => Math.imul(acc ^ char.charCodeAt(0), 16777619) >>> 0,
    2166136261
  );
  return AUTO_THEMES[hash % AUTO_THEMES.length];
};

export const coverThemeFor = account =>
  COVER_THEMES[account?.cover_theme]
    ? account.cover_theme
    : autoCoverTheme(account?.name);

export const coverClassFor = account => COVER_THEMES[coverThemeFor(account)];

export const workspaceInitials = (name = '') => {
  const words = name
    .replace(/[^\p{L}\p{N}\s]/gu, ' ')
    .split(/\s+/)
    .filter(Boolean);
  if (!words.length) return '?';
  if (words.length === 1) return words[0].slice(0, 2).toUpperCase();
  return (words[0][0] + words[1][0]).toUpperCase();
};

const RELATIVE_STEPS = [
  ['year', 31536000],
  ['month', 2592000],
  ['week', 604800],
  ['day', 86400],
  ['hour', 3600],
  ['minute', 60],
];

// "2 days ago" / "há 2 dias" in the interface language; empty when the user
// never opened the workspace.
export const formatLastAccess = (
  timestamp,
  locale = 'en',
  now = Date.now()
) => {
  if (!timestamp) return '';
  const seconds = Math.round((new Date(timestamp).getTime() - now) / 1000);
  const formatter = new Intl.RelativeTimeFormat(locale.replace('_', '-'), {
    numeric: 'auto',
  });
  const [unit, size] = RELATIVE_STEPS.find(
    ([, step]) => Math.abs(seconds) >= step
  ) || ['minute', 60];
  return formatter.format(Math.round(seconds / size), unit);
};
