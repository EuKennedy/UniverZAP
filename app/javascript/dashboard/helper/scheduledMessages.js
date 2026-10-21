// Funções puras das mensagens agendadas: atalhos de horário, conversão do
// <input type="datetime-local"> e a prévia das variáveis. Sem store, sem API,
// para o vitest cobrir direto.

export const VARIABLES = [
  'primeiro_nome',
  'nome',
  'servico',
  'profissional',
  'ultima_visita',
];

const atHour = (date, hour, minute = 0) => {
  const copy = new Date(date);
  copy.setHours(hour, minute, 0, 0);
  return copy;
};

const addDays = (date, days) => {
  const copy = new Date(date);
  copy.setDate(copy.getDate() + days);
  return copy;
};

// Atalhos que o atendente mais usa. `bestAt` (ISO) vem do backend quando a
// cliente tem um horário em que costuma responder.
export const buildShortcuts = (now = new Date(), bestAt = null) => {
  const list = [];
  const inOneHour = new Date(now.getTime() + 60 * 60 * 1000);
  inOneHour.setSeconds(0, 0);
  list.push({ key: 'IN_1_HOUR', at: inOneHour });
  if (now.getHours() < 17) list.push({ key: 'TODAY_18', at: atHour(now, 18) });
  list.push({ key: 'TOMORROW_9', at: atHour(addDays(now, 1), 9) });
  list.push({ key: 'IN_3_DAYS', at: atHour(addDays(now, 3), 10) });
  const daysToMonday = (8 - now.getDay()) % 7 || 7;
  list.push({
    key: 'MONDAY_MORNING',
    at: atHour(addDays(now, daysToMonday), 9),
  });
  if (bestAt) list.push({ key: 'BEST_TIME', at: new Date(bestAt), best: true });
  return list;
};

export const toDateTimeLocal = value => {
  if (!value) return '';
  const date = new Date(value);
  const offset = date.getTimezoneOffset() * 60000;
  return new Date(date.getTime() - offset).toISOString().slice(0, 16);
};

export const fromDateTimeLocal = value =>
  value ? new Date(value).toISOString() : null;

// Mesma regra do backend (Broadcasts::MessageRenderer#clean_name): nome que é
// telefone ou e-mail não vira "Oi +55 31…".
export const firstNameOf = name => {
  const clean = String(name || '')
    .replace(/~/g, '')
    .trim();
  if (!clean || /\d{4,}|@/.test(clean)) return '';
  const first = clean.split(/\s+/)[0].replace(/[^\p{L}\p{M}'.-]/gu, '');
  return first
    ? first.charAt(0).toUpperCase() + first.slice(1).toLowerCase()
    : '';
};

// Exemplo do que a cliente recebe: spintax pela primeira opção e variáveis
// preenchidas com o que a tela já sabe. O texto real é montado no envio.
export const previewText = (text, { contact = {}, conversation = {} } = {}) => {
  const attrs = conversation.custom_attributes || {};
  const contactAttrs = contact.custom_attributes || {};
  const values = {
    nome: contact.name || '',
    primeiro_nome: firstNameOf(contact.name),
    servico: attrs.servico || contactAttrs.servico || '',
    profissional: attrs.profissional || contactAttrs.profissional || '',
    ultima_visita: contactAttrs.ultima_visita || '',
  };
  let result = String(text || '');
  const spin = /\{([^{}]*\|[^{}]*)\}/;
  while (spin.test(result)) {
    result = result.replace(spin, (_, options) => options.split('|')[0]);
  }
  return result
    .replace(/\{(\w+)\}/g, (match, key) =>
      key in values ? values[key] : match
    )
    .replace(/[ \t]{2,}/g, ' ')
    .trim();
};

export const missingVariables = (text, context) => {
  const used = [...String(text || '').matchAll(/\{(\w+)\}/g)].map(m => m[1]);
  return [...new Set(used)].filter(
    key => VARIABLES.includes(key) && !previewText(`{${key}}`, context).trim()
  );
};

// Mensagens pendentes primeiro, por horário; depois as que já resolveram.
export const sortScheduled = list =>
  [...list].sort((a, b) => {
    const pendingA = a.status === 'scheduled' ? 0 : 1;
    const pendingB = b.status === 'scheduled' ? 0 : 1;
    if (pendingA !== pendingB) return pendingA - pendingB;
    return new Date(a.send_at) - new Date(b.send_at);
  });
