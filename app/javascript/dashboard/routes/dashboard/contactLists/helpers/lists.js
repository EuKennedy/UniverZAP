// Regras puras das telas de Listas (filtro, selos, cartões de métrica), fora
// dos componentes para terem teste próprio.

export const SOURCES = ['group', 'csv', 'manual', 'filter'];
export const MEMBER_FILTERS = [
  'all',
  'active',
  'new',
  'left',
  'no_phone',
  'cold',
];

export const SOURCE_META = {
  group: { icon: 'i-lucide-users-round', tone: 'bg-n-teal-3 text-n-teal-11' },
  csv: {
    icon: 'i-lucide-file-spreadsheet',
    tone: 'bg-n-iris-3 text-n-iris-11',
  },
  manual: { icon: 'i-lucide-hand', tone: 'bg-n-alpha-2 text-n-slate-11' },
  filter: { icon: 'i-lucide-filter', tone: 'bg-n-amber-3 text-n-amber-11' },
};

const normalize = text =>
  (text || '').toString().normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

// Busca sem acento por nome, descrição e grupo; origem opcional.
export const filterLists = (lists, { query = '', source = '' } = {}) => {
  const needle = normalize(query.trim());
  return lists.filter(list => {
    if (source && list.source !== source) return false;
    if (!needle) return true;
    return [list.name, list.description, list.group_name].some(value =>
      normalize(value).includes(needle)
    );
  });
};

// Os selos de um membro, na ordem em que importam para quem vai disparar.
export const memberBadges = member => {
  const badges = [];
  if (member.status === 'left') badges.push('LEFT');
  if (member.is_new) badges.push('NEW');
  if (!member.phone) badges.push('NO_PHONE');
  if (member.cold) badges.push('COLD');
  if (['admin', 'superadmin'].includes(member.role)) badges.push('ADMIN');
  return badges;
};

export const BADGE_TONES = {
  LEFT: 'bg-n-alpha-2 text-n-slate-11',
  NEW: 'bg-n-teal-3 text-n-teal-11',
  NO_PHONE: 'bg-n-ruby-3 text-n-ruby-11',
  COLD: 'bg-n-amber-3 text-n-amber-11',
  ADMIN: 'bg-n-iris-3 text-n-iris-11',
};

// Cartões do topo do detalhe: quem pode receber, quem precisa de confirmação
// e quem nunca recebe.
export const summaryCards = (summary = {}) => [
  {
    key: 'ACTIVE',
    icon: 'i-lucide-users',
    tone: 'bg-n-brand/10 text-n-teal-11',
    value: summary.active ?? 0,
  },
  {
    key: 'SENDABLE',
    icon: 'i-lucide-send',
    tone: 'bg-n-teal-3 text-n-teal-11',
    value: summary.sendable ?? 0,
  },
  {
    key: 'COLD',
    icon: 'i-lucide-shield-alert',
    tone: 'bg-n-amber-3 text-n-amber-11',
    value: summary.unconsented ?? 0,
  },
  {
    key: 'NO_PHONE',
    icon: 'i-lucide-phone-off',
    tone: 'bg-n-ruby-3 text-n-ruby-11',
    value: summary.no_phone ?? 0,
  },
  {
    key: 'LEFT',
    icon: 'i-lucide-log-out',
    tone: 'bg-n-alpha-2 text-n-slate-11',
    value: summary.left ?? 0,
  },
];

// "Atualizado há…" em linguagem de gente, a partir de segundos Unix.
export const relativeTime = (seconds, locale = 'pt-BR', now = Date.now()) => {
  if (!seconds) return '';
  const diff = Math.round((seconds * 1000 - now) / 1000);
  const units = [
    ['day', 86400],
    ['hour', 3600],
    ['minute', 60],
  ];
  // O vue-i18n usa "pt_BR"; o Intl só aceita a tag BCP 47 ("pt-BR").
  const formatter = new Intl.RelativeTimeFormat(locale.replace('_', '-'), {
    numeric: 'auto',
  });
  const found = units.find(([, size]) => Math.abs(diff) >= size);
  if (!found) return formatter.format(0, 'minute');
  const [unit, size] = found;
  return formatter.format(Math.round(diff / size), unit);
};

// A primeira linha de um CSV colado, para a prévia da importação.
export const previewCsv = (text, limit = 5) =>
  (text || '')
    .split(/\r?\n/)
    .map(line => line.trim())
    .filter(Boolean)
    .slice(0, limit);

export const downloadBlob = (blob, filename) => {
  const url = window.URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  link.click();
  window.URL.revokeObjectURL(url);
};
