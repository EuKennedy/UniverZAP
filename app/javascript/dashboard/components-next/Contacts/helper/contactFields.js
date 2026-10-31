import countries from 'shared/constants/countries';
import {
  AD_ORIGIN,
  formatPhone,
} from 'dashboard/routes/dashboard/conversation/contact/helpers/customerSheet';

const WHATSAPP_HANDLE = /^(\+?\d+)@(c\.us|s\.whatsapp\.net)$/i;
const LID_HANDLE = /@lid$/i;
const ONLY_DIGITS = /^\+?\d{8,}$/;

// Attributes that already have a column of their own.
const OWN_COLUMN_ATTRIBUTES = ['recorrente', 'origem_lead'];

// Every field the page can show, in display order. `belezaki` fields come from
// the salon and only load after the user turns them on.
export const STANDARD_FIELDS = [
  { key: 'phone', sort: 'phone_number' },
  { key: 'email', sort: 'email' },
  { key: 'labels' },
  { key: 'type' },
  { key: 'origin' },
  { key: 'company', sort: 'company_name' },
  { key: 'location', sort: 'city' },
  { key: 'identifier' },
  { key: 'createdAt', sort: 'created_at' },
  { key: 'lastActivity', sort: 'last_activity_at' },
];

export const BELEZAKI_FIELDS = [
  { key: 'belezakiNext', belezaki: true },
  { key: 'belezakiServices', belezaki: true },
  { key: 'belezakiProfessional', belezaki: true },
  { key: 'belezakiSpent', belezaki: true },
  { key: 'belezakiVisits', belezaki: true },
];

export const customFields = (attributes = []) =>
  attributes
    .filter(({ attributeKey }) => !OWN_COLUMN_ATTRIBUTES.includes(attributeKey))
    .map(attribute => ({
      key: `custom:${attribute.attributeKey}`,
      custom: true,
      attributeKey: attribute.attributeKey,
      name: attribute.attributeDisplayName,
      displayType: attribute.attributeDisplayType,
    }));

const whatsappNumber = value => String(value || '').match(WHATSAPP_HANDLE)?.[1];

// The real number, or the one a "553398300240@c.us" handle spells out.
export const contactPhone = (contact = {}) => {
  const digits =
    contact.phoneNumber ||
    whatsappNumber(contact.name) ||
    whatsappNumber(contact.identifier);
  if (!digits) return '';
  return formatPhone(digits.startsWith('+') ? digits : `+${digits}`);
};

export const hasRawName = ({ name } = {}) => {
  const value = String(name || '').trim();
  return (
    !value ||
    LID_HANDLE.test(value) ||
    WHATSAPP_HANDLE.test(value) ||
    ONLY_DIGITS.test(value)
  );
};

// A person's name, never a WhatsApp handle: the number when the name is only
// the handle, and null when there is nothing readable to show.
export const contactTitle = contact =>
  hasRawName(contact) ? contactPhone(contact) || null : contact.name;

export const contactType = ({ customAttributes } = {}) =>
  [true, 'true'].includes(customAttributes?.recorrente) ? 'recurring' : 'new';

export const contactOrigin = ({ customAttributes } = {}) => {
  const origin = customAttributes?.origem_lead;
  if (!origin) return null;
  if (origin === AD_ORIGIN) return 'ad';
  return origin === 'organico' ? 'organic' : origin;
};

export const contactLocation = ({ additionalAttributes } = {}) => {
  const { city, country, countryCode } = additionalAttributes || {};
  const code = countryCode || country;
  const countryName = countries.find(({ id }) => id === code)?.name || country;
  return [city, countryName].filter(Boolean).join(', ');
};

const toIntlLocale = locale => String(locale || 'en').replace('_', '-');

export const formatDate = (epoch, locale) =>
  epoch
    ? new Intl.DateTimeFormat(toIntlLocale(locale), {
        day: '2-digit',
        month: '2-digit',
        year: 'numeric',
      }).format(new Date(epoch * 1000))
    : '';

const RELATIVE_UNITS = [
  ['year', 31536000],
  ['month', 2592000],
  ['day', 86400],
  ['hour', 3600],
  ['minute', 60],
];

export const formatRelative = (epoch, locale, now = Date.now()) => {
  if (!epoch) return '';
  const seconds = Math.round(epoch - now / 1000);
  const [unit, size] = RELATIVE_UNITS.find(
    ([, length]) => Math.abs(seconds) >= length
  ) || ['minute', 60];
  return new Intl.RelativeTimeFormat(toIntlLocale(locale), {
    numeric: 'auto',
  }).format(Math.round(seconds / size), unit);
};
