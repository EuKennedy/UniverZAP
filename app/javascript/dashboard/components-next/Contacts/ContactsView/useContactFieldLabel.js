import { useI18n } from 'vue-i18n';

const snakeUpper = key => key.replace(/[A-Z]/g, c => `_${c}`).toUpperCase();

// Custom attributes carry their own name; the rest live in the locale files.
export function useContactFieldLabel() {
  const { t } = useI18n();
  return field =>
    field.custom
      ? field.name
      : t(`CONTACTS_LAYOUT.FIELDS.${snakeUpper(field.key)}`);
}
