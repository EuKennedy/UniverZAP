// Funções puras da lista de campanhas: busca, filtro, paginação e os números
// de cada cartão/linha. Sem store, para o vitest cobrir direto.

export const STATUSES = [
  'draft',
  'scheduled',
  'running',
  'paused',
  'completed',
];
export const PAGE_SIZES = [12, 24, 48];

export const COLUMNS = [
  { key: 'status', default: true },
  { key: 'inbox', default: true },
  { key: 'progress', default: true },
  { key: 'replied', default: true },
  { key: 'skipped', default: true },
  { key: 'failed', default: true },
  { key: 'created', default: false },
];

export const defaultColumns = () =>
  COLUMNS.filter(column => column.default).map(column => column.key);

const normalize = text =>
  String(text || '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase();

export const filterBroadcasts = (list, { query = '', status = '' } = {}) => {
  const needle = normalize(query.trim());
  return [...list]
    .filter(item => !status || item.status === status)
    .filter(item => !needle || normalize(item.name).includes(needle))
    .sort((a, b) => b.id - a.id);
};

export const paginate = (list, page, size) => {
  const totalPages = Math.max(1, Math.ceil(list.length / size));
  const current = Math.min(Math.max(1, page), totalPages);
  const start = (current - 1) * size;
  const end = Math.min(start + size, list.length);
  return {
    items: list.slice(start, end),
    page: current,
    totalPages,
    start,
    end,
  };
};

// No máximo 7 botões de página, com a janela andando junto da atual.
export const pageWindow = (current, total) => {
  let first = Math.max(1, current - 3);
  const last = Math.min(total, first + 6);
  first = Math.max(1, last - 6);
  return Array.from({ length: last - first + 1 }, (_, i) => first + i);
};

// Processados = enviados + falhas + pulados; o resto ainda espera a vez.
export const progressOf = item => {
  const total = Number(item.recipients_count) || 0;
  if (!total) return 0;
  const done =
    (Number(item.sent_count) || 0) +
    (Number(item.failed_count) || 0) +
    (Number(item.skipped_count) || 0);
  return Math.min(100, Math.round((done / total) * 100));
};

export const replyRateOf = item => {
  const sent = Number(item.sent_count) || 0;
  return sent
    ? Math.round(((Number(item.replied_count) || 0) / sent) * 100)
    : null;
};

export const usageTone = (used, cap) => {
  const ratio = cap ? used / cap : 0;
  if (ratio >= 0.9) return 'bg-n-ruby-9';
  if (ratio >= 0.6) return 'bg-n-amber-9';
  return 'bg-n-teal-9';
};

// Barra em doze avos: Tailwind sem estilo inline.
const WIDTHS = [
  'w-0',
  'w-1/12',
  'w-2/12',
  'w-3/12',
  'w-4/12',
  'w-5/12',
  'w-6/12',
  'w-7/12',
  'w-8/12',
  'w-9/12',
  'w-10/12',
  'w-11/12',
  'w-full',
];
export const widthClass = ratio =>
  WIDTHS[Math.min(12, Math.max(0, Math.round((Number(ratio) || 0) * 12)))];

// Enviadas → entregues → lidas → responderam, cada etapa sobre as enviadas.
export const funnelOf = counts => {
  const sent = Number(counts.sent) || 0;
  return ['sent', 'delivered', 'read', 'replied'].map(key => {
    const value = Number(counts[key]) || 0;
    return { key, value, ratio: sent ? value / sent : 0 };
  });
};

export const REPORT_FILTERS = [
  'all',
  'sent',
  'delivered',
  'read',
  'replied',
  'failed',
  'skipped',
  'pending',
];
