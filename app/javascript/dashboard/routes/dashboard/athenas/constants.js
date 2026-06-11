// Shared option lists for the Athenas assistant pages. Labels resolve through
// i18n at render time (see ATHENAS.TONES.* and ATHENAS.WIZARD.KNOWLEDGE.CATEGORIES.*),
// so Wizard and Edit can never drift apart again.
export const TONE_OPTIONS = [
  {
    key: 'sales',
    labelKey: 'ATHENAS.TONES.SALES',
    icon: 'i-lucide-trending-up',
  },
  {
    key: 'support',
    labelKey: 'ATHENAS.TONES.SUPPORT',
    icon: 'i-lucide-life-buoy',
  },
  {
    key: 'friendly',
    labelKey: 'ATHENAS.TONES.FRIENDLY',
    icon: 'i-lucide-smile',
  },
  {
    key: 'formal',
    labelKey: 'ATHENAS.TONES.FORMAL',
    icon: 'i-lucide-briefcase',
  },
  {
    key: 'concierge',
    labelKey: 'ATHENAS.TONES.CONCIERGE',
    icon: 'i-lucide-crown',
  },
];

export const TRAINING_CATEGORY_OPTIONS = [
  { key: 'base', labelKey: 'ATHENAS.WIZARD.KNOWLEDGE.CATEGORIES.BASE' },
  { key: 'catalog', labelKey: 'ATHENAS.WIZARD.KNOWLEDGE.CATEGORIES.CATALOG' },
  { key: 'policies', labelKey: 'ATHENAS.WIZARD.KNOWLEDGE.CATEGORIES.POLICIES' },
  { key: 'sales', labelKey: 'ATHENAS.WIZARD.KNOWLEDGE.CATEGORIES.SALES' },
  { key: 'faq', labelKey: 'ATHENAS.WIZARD.KNOWLEDGE.CATEGORIES.FAQ' },
  { key: 'support', labelKey: 'ATHENAS.WIZARD.KNOWLEDGE.CATEGORIES.SUPPORT' },
];
