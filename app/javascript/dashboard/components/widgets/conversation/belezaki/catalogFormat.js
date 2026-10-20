// A professional's week, as the salon stores it (weekday 0 = Sunday, 'HH:MM'
// windows), folded into runs of days with the same hours: "seg–sex 09:00–18:00,
// sáb 09:00–14:00". Weekday names come from the locale.
const weekdayName = (weekday, locale) =>
  new Intl.DateTimeFormat(locale.replace('_', '-'), { weekday: 'short' })
    .format(new Date(Date.UTC(2023, 0, 1 + weekday, 12)))
    .replace('.', '');

export const scheduleSummary = (schedule = [], locale = 'pt-BR') => {
  const days = [...schedule]
    .filter(w => typeof w.weekday === 'number' && w.start && w.end)
    .sort((a, b) => a.weekday - b.weekday);
  const runs = [];
  days.forEach(w => {
    const last = runs[runs.length - 1];
    const sameHours = last && last.start === w.start && last.end === w.end;
    if (sameHours && last.to === w.weekday - 1) {
      last.to = w.weekday;
    } else {
      runs.push({ from: w.weekday, to: w.weekday, start: w.start, end: w.end });
    }
  });
  return runs
    .map(r => {
      const span =
        r.from === r.to
          ? weekdayName(r.from, locale)
          : `${weekdayName(r.from, locale)}–${weekdayName(r.to, locale)}`;
      return `${span} ${r.start}–${r.end}`;
    })
    .join(', ');
};

const normalise = text =>
  String(text || '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase();

// Case- and accent-insensitive: "coloracao" finds "Coloração".
export const matches = (query, ...fields) => {
  const q = normalise(query).trim();
  if (!q) return true;
  return fields.some(f => normalise(f).includes(q));
};
