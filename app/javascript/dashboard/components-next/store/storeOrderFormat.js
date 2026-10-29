// Money and dates for the store card, short enough to share a line.
const tag = locale => locale.replace('_', '-');

export const formatMoney = (value, locale, currency = 'BRL') =>
  new Intl.NumberFormat(tag(locale), { style: 'currency', currency }).format(
    Number(value) || 0
  );

// "29 out" this year, "08 ago 2025" before it: the day and the month without
// the "de" and the dot pt-BR puts in between.
export const formatShortDate = (value, locale) => {
  const date = new Date(value);
  if (!value || Number.isNaN(date.getTime())) return '—';
  const sameYear = date.getFullYear() === new Date().getFullYear();
  const parts = new Intl.DateTimeFormat(tag(locale), {
    day: '2-digit',
    month: 'short',
    ...(sameYear ? {} : { year: 'numeric' }),
  }).formatToParts(date);
  return parts
    .filter(part => ['day', 'month', 'year'].includes(part.type))
    .map(part => part.value.replace('.', ''))
    .join(' ');
};
