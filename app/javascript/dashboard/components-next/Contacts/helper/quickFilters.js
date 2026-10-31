// The chips of the toolbar are shortcuts into the advanced filter: each one is
// a regular condition in the store, so the filter dialog, the saved segments
// and the export all see them without knowing they exist.
const QUICK_FILTER_KEYS = {
  labels: 'labels',
  origin: 'origem_lead',
  type: 'recorrente',
  period: 'created_at',
  phone: 'phone_number',
};

const condition = (key, operator, values, attributeModel = 'standard') => ({
  attribute_key: key,
  filter_operator: operator,
  values,
  query_operator: 'and',
  attribute_model: attributeModel,
});

const isoDay = date => date.toISOString().slice(0, 10);

export const PERIOD_DAYS = [7, 30, 90, 365];

const BUILDERS = {
  labels: labels =>
    labels.length
      ? condition(
          QUICK_FILTER_KEYS.labels,
          'equal_to',
          labels.map(title => ({ id: title, name: title }))
        )
      : null,
  origin: origin =>
    condition(QUICK_FILTER_KEYS.origin, 'equal_to', origin, 'customAttributes'),
  type: type =>
    condition(
      QUICK_FILTER_KEYS.type,
      type === 'recurring' ? 'equal_to' : 'not_equal_to',
      { id: true, name: 'true' },
      'customAttributes'
    ),
  period: (days, now = new Date()) =>
    condition(
      QUICK_FILTER_KEYS.period,
      'is_greater_than',
      isoDay(new Date(now.getTime() - days * 86400000))
    ),
  phone: phone =>
    condition(
      QUICK_FILTER_KEYS.phone,
      phone === 'with' ? 'is_present' : 'is_not_present',
      ''
    ),
};

// `value` empty clears the chip. Conditions of the advanced filter that no chip
// owns are left exactly as they are.
export const withQuickFilter = (filters, name, value, now) => {
  const others = filters.filter(
    item => item.attribute_key !== QUICK_FILTER_KEYS[name]
  );
  const next = value ? BUILDERS[name](value, now) : null;
  return next ? [...others, next] : others;
};

const find = (filters, name) =>
  filters.find(item => item.attribute_key === QUICK_FILTER_KEYS[name]);

const daysSince = (value, now) =>
  Math.floor((now.getTime() - new Date(value).getTime()) / 86400000);

// What each chip reads as, from the conditions in the store.
export const quickFilterState = (filters, now = new Date()) => {
  const labels = find(filters, 'labels');
  const type = find(filters, 'type');
  const period = find(filters, 'period');
  const phone = find(filters, 'phone');
  const presence = { is_present: 'with', is_not_present: 'without' };

  return {
    labels: (labels?.filter_operator === 'equal_to' && labels.values) || [],
    origin: find(filters, 'origin')?.values || null,
    type: type && (type.filter_operator === 'equal_to' ? 'recurring' : 'new'),
    period:
      period?.filter_operator === 'is_greater_than'
        ? PERIOD_DAYS.find(days => days === daysSince(period.values, now))
        : null,
    phone: presence[phone?.filter_operator] || null,
  };
};

const CHIP_OPERATORS = {
  labels: ['equal_to'],
  origem_lead: ['equal_to'],
  recorrente: ['equal_to', 'not_equal_to'],
  created_at: ['is_greater_than'],
  phone_number: ['is_present', 'is_not_present'],
};

// False when a condition from the advanced filter has no chip to show it, so
// the summary of active filters is still needed.
export const allConditionsHaveChips = (filters, now = new Date()) =>
  filters.every(
    ({ attribute_key: key, filter_operator: operator }) =>
      CHIP_OPERATORS[key]?.includes(operator) &&
      (key !== 'created_at' || quickFilterState(filters, now).period)
  );
