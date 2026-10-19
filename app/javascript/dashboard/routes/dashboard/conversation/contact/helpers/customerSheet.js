import { parsePhoneNumber } from 'libphonenumber-js';

// Values stamped by Conversations::AdReferralService / the beauty_salon template.
export const AD_ORIGIN = 'anuncio_facebook';
export const AD_LABEL = 'lead-anuncio';
export const SCHEDULE_FIELDS = [
  'servico',
  'profissional',
  'data_agendamento',
  'ciclo_recompra_semanas',
];

const endsWithLid = value => /@lid$/i.test(String(value || ''));

// WAHA creates ad-hoc contacts whose only handle is a LID (no phone, name
// "…@lid"); the sheet says "no number" instead of showing the handle.
export const isLidContact = (contact = {}) =>
  !contact.phone_number &&
  (endsWithLid(contact.identifier) || endsWithLid(contact.name));

export const formatPhone = phone => {
  if (!phone) return '';
  try {
    return parsePhoneNumber(phone).formatInternational();
  } catch {
    return phone;
  }
};

// Ad or organic. The conversation knows when it started from an ad; the
// contact remembers its first touch (origem_lead) for later conversations.
export const originOf = (conversation = {}, contact = {}) => {
  const attrs = conversation.custom_attributes || {};
  const labels = conversation.labels || [];
  if (
    attrs.origem_lead === AD_ORIGIN ||
    attrs.anuncio_id ||
    labels.includes(AD_LABEL)
  ) {
    return {
      source: 'ad',
      title: attrs.anuncio_titulo || attrs.anuncio_id || '',
      url: attrs.anuncio_url || '',
    };
  }
  if ((contact.custom_attributes || {}).origem_lead === AD_ORIGIN) {
    return { source: 'ad', title: '', url: '' };
  }
  return { source: 'organic', title: '', url: '' };
};

// New or recurring. Trusts the contact's `recorrente` attribute when it is
// set; otherwise a customer is recurring when another conversation of
// theirs already closed (resolved, or carrying a closing stage).
export const customerTypeOf = ({
  contact = {},
  conversation = {},
  previousConversations = [],
  closingTitles = [],
}) => {
  const recurring = (contact.custom_attributes || {}).recorrente;
  if (recurring === true || recurring === 'true') return 'recurring';
  if (recurring === false || recurring === 'false') return 'new';

  const hasClosedConversation = previousConversations.some(
    other =>
      other.id !== conversation.id &&
      (other.status === 'resolved' ||
        (other.labels || []).some(label => closingTitles.includes(label)))
  );
  return hasClosedConversation ? 'recurring' : 'new';
};

// The vertical's stage carried by the conversation, in the vertical's order.
export const stageOf = (labels = [], stages = []) =>
  stages.find(stage => labels.includes(stage.title)) || null;

const toIntlLocale = locale => String(locale || 'en').replace('_', '-');

// "sáb., 25/10, 14:00". A date-only value (what the generic attribute
// editor saves) shows without a time, parsed as a local day.
export const formatAppointment = (value, locale = 'en') => {
  if (!value) return '';
  const intlLocale = toIntlLocale(locale);
  if (/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    const [year, month, day] = value.split('-').map(Number);
    return new Date(year, month - 1, day).toLocaleDateString(intlLocale, {
      weekday: 'short',
      day: '2-digit',
      month: '2-digit',
    });
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return date.toLocaleString(intlLocale, {
    weekday: 'short',
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
};

// Prefills an <input type="datetime-local"> from a stored value.
export const toDateTimeLocal = value => {
  if (!value) return '';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  const pad = number => String(number).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(
    date.getDate()
  )}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
};

// What a datetime-local input gives back, stored as ISO 8601.
export const fromDateTimeLocal = value => {
  if (!value) return '';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? '' : date.toISOString();
};
