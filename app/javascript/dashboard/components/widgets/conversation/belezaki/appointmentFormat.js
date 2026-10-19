// The salon answers ISO 8601 with its own offset and names its timezone, so a
// time is shown in the salon's clock whatever the agent's browser is set to.
export const formatStart = (iso, timeZone, locale = 'pt-BR') => {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return '';
  return new Intl.DateTimeFormat(locale.replace('_', '-'), {
    weekday: 'short',
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
    ...(timeZone ? { timeZone } : {}),
  }).format(date);
};

export const STATUS_CLASSES = {
  confirmed: 'bg-n-teal-5 text-n-teal-12',
  scheduled: 'bg-n-teal-5 text-n-teal-12',
  done: 'bg-n-slate-3 text-n-slate-12',
  no_show: 'bg-n-ruby-5 text-n-ruby-12',
  cancelled: 'bg-n-ruby-5 text-n-ruby-12',
  cancelled_client: 'bg-n-ruby-5 text-n-ruby-12',
};

export const statusClass = status =>
  STATUS_CLASSES[status] || 'bg-n-slate-3 text-n-slate-12';
