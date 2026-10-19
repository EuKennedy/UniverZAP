/**
 * Formatting shared by the Painel blocks. Durations come from the API in
 * seconds (medians of first_reply_created_at - created_at, or time since
 * waiting_since) and are shown in the coarsest unit that still says something.
 */
export const rate = (part, total) =>
  total ? `${Math.round((part / total) * 100)}%` : '';

export const formatSeconds = (seconds, t) => {
  if (seconds === null || seconds === undefined) return '—';
  const total = Math.max(0, Math.round(Number(seconds)));
  if (total < 60) return t('PANEL_REPORTS.DURATION.SECONDS', { n: total });
  const minutes = Math.round(total / 60);
  if (minutes < 60) return t('PANEL_REPORTS.DURATION.MINUTES', { n: minutes });
  const hours = Math.floor(minutes / 60);
  if (hours < 24) {
    return t('PANEL_REPORTS.DURATION.HOURS', { h: hours, m: minutes % 60 });
  }
  return t('PANEL_REPORTS.DURATION.DAYS', {
    d: Math.floor(hours / 24),
    h: hours % 24,
  });
};

export const secondsSince = isoDate =>
  isoDate ? (Date.now() - new Date(isoDate).getTime()) / 1000 : null;
