// The salon answers ISO 8601 with its own offset and names its timezone, so a
// time is shown in the salon's clock whatever the agent's browser is set to.
const tag = locale => locale.replace('_', '-');

export const formatStart = (iso, timeZone, locale = 'pt-BR') => {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return '';
  return new Intl.DateTimeFormat(tag(locale), {
    weekday: 'short',
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
    ...(timeZone ? { timeZone } : {}),
  }).format(date);
};

export const formatDay = (iso, timeZone, locale = 'pt-BR') => {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return '';
  return new Intl.DateTimeFormat(tag(locale), {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    ...(timeZone ? { timeZone } : {}),
  }).format(date);
};

// Money comes in cents, in the salon's currency (BRL for every salon today).
export const formatMoney = (cents, locale = 'pt-BR') =>
  new Intl.NumberFormat(tag(locale), {
    style: 'currency',
    currency: 'BRL',
    maximumFractionDigits: 2,
  }).format((Number(cents) || 0) / 100);

export const STATUS_CLASSES = {
  confirmed: 'bg-n-teal-5 text-n-teal-12',
  scheduled: 'bg-n-blue-5 text-n-blue-12',
  done: 'bg-n-slate-3 text-n-slate-12',
  no_show: 'bg-n-ruby-5 text-n-ruby-12',
  cancelled: 'bg-n-ruby-5 text-n-ruby-12',
  cancelled_client: 'bg-n-ruby-5 text-n-ruby-12',
};

export const statusClass = status =>
  STATUS_CLASSES[status] || 'bg-n-slate-3 text-n-slate-12';
