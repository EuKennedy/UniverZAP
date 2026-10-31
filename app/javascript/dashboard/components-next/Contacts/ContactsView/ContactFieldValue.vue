<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  formatDay,
  formatMoney,
  formatStart,
} from 'dashboard/components/widgets/conversation/belezaki/appointmentFormat';
import {
  contactLocation,
  contactOrigin,
  contactPhone,
  contactType,
  formatDate,
  formatRelative,
} from '../helper/contactFields';

const props = defineProps({
  field: { type: Object, required: true },
  contact: { type: Object, required: true },
  // Label title → color, for the whole page.
  labelColors: { type: Object, default: () => ({}) },
  // This contact's belezaki summary; undefined while it has not arrived.
  summary: { type: Object, default: undefined },
  // Cells stay on one line; the side panel has room for everything.
  wrap: { type: Boolean, default: false },
});

const { t, locale } = useI18n();

const MAX_LABELS = 2;

const TYPE_TONES = {
  new: 'bg-n-teal-3 text-n-teal-11',
  recurring: 'bg-n-iris-3 text-n-iris-11',
};
const ORIGIN_TONES = {
  ad: 'bg-n-amber-3 text-n-amber-11',
  organic: 'bg-n-slate-3 text-n-slate-11',
};

const type = computed(() => contactType(props.contact));
const origin = computed(() => contactOrigin(props.contact));
const originLabel = computed(() => {
  if (origin.value === 'ad') return t('CONTACTS_LAYOUT.FIELDS.ORIGIN_AD');
  if (origin.value === 'organic')
    return t('CONTACTS_LAYOUT.FIELDS.ORIGIN_ORGANIC');
  return origin.value;
});

const labels = computed(() => props.contact.labels || []);
const shownLabels = computed(() =>
  props.wrap ? labels.value : labels.value.slice(0, MAX_LABELS)
);
const extraLabels = computed(
  () => labels.value.length - shownLabels.value.length
);

const customValue = computed(() => {
  const { attributeKey, displayType } = props.field;
  const value = props.contact.customAttributes?.[attributeKey];
  if (value === undefined || value === null || value === '') return '';
  if (displayType === 'checkbox') {
    return t(`CONTACTS_LAYOUT.FIELDS.${value ? 'YES' : 'NO'}`);
  }
  if (displayType === 'date') {
    return new Date(value).toLocaleDateString(locale.value.replace('_', '-'));
  }
  return String(value);
});
const customIsLink = computed(() => props.field.displayType === 'link');

const belezaki = computed(() =>
  props.summary?.status === 'ok' ? props.summary : null
);
const isBelezakiLoading = computed(
  () => props.field.belezaki && !props.summary
);

const belezakiText = computed(() => {
  const data = belezaki.value;
  if (!data) return '';
  const money = cents =>
    cents === null || cents === undefined
      ? ''
      : formatMoney(cents, locale.value);
  return {
    belezakiNext:
      data.next && formatStart(data.next.start, data.timezone, locale.value),
    belezakiServices: (data.last_services || []).join(', '),
    belezakiProfessional: data.professional,
    belezakiSpent: money(data.total_spent_cents),
    belezakiVisits: data.last_visit_at
      ? `${data.visits ?? 0} · ${formatDay(data.last_visit_at, data.timezone, locale.value)}`
      : data.visits,
  }[props.field.key];
});

const text = computed(() => {
  const { contact, field } = props;
  if (field.custom) return customValue.value;
  if (field.belezaki) return belezakiText.value;
  return {
    phone: contactPhone(contact),
    email: contact.email,
    company: contact.additionalAttributes?.companyName,
    location: contactLocation(contact),
    identifier: contact.identifier,
    createdAt: formatDate(contact.createdAt, locale.value),
    lastActivity: formatRelative(contact.lastActivityAt, locale.value),
  }[field.key];
});

const belezakiHint = computed(() => {
  const { field, summary } = props;
  if (field.key !== 'belezakiNext') return '';
  return summary?.status === 'unknown_client'
    ? t('CONTACTS_LAYOUT.FIELDS.BELEZAKI_UNKNOWN')
    : '';
});
</script>

<template>
  <span
    v-if="isBelezakiLoading"
    class="block w-20 h-3 rounded animate-pulse bg-n-alpha-2"
  />

  <span
    v-else-if="field.key === 'type'"
    class="inline-flex px-2 py-0.5 text-xs font-medium rounded-md whitespace-nowrap"
    :class="TYPE_TONES[type]"
  >
    {{
      t(
        type === 'recurring'
          ? 'CONTACTS_LAYOUT.FIELDS.TYPE_RECURRING'
          : 'CONTACTS_LAYOUT.FIELDS.TYPE_NEW'
      )
    }}
  </span>

  <span
    v-else-if="field.key === 'origin' && origin"
    class="inline-flex px-2 py-0.5 text-xs font-medium rounded-md whitespace-nowrap"
    :class="ORIGIN_TONES[origin] || ORIGIN_TONES.organic"
  >
    {{ originLabel }}
  </span>

  <span
    v-else-if="field.key === 'labels' && labels.length"
    class="flex items-center gap-1"
    :class="{ 'flex-wrap': wrap }"
    :title="labels.join(', ')"
  >
    <span
      v-for="label in shownLabels"
      :key="label"
      class="inline-flex items-center gap-1 px-1.5 py-0.5 text-xs rounded-md bg-n-alpha-2 text-n-slate-12 max-w-32"
    >
      <span
        class="flex-shrink-0 rounded-sm size-2"
        :style="{ backgroundColor: labelColors[label] }"
      />
      <span class="truncate">{{ label }}</span>
    </span>
    <span v-if="extraLabels" class="text-xs text-n-slate-10">
      +{{ extraLabels }}
    </span>
  </span>

  <a
    v-else-if="field.custom && customIsLink && text"
    :href="text"
    target="_blank"
    rel="noopener noreferrer"
    class="block truncate text-n-teal-11 hover:underline"
    @click.stop
  >
    {{ text }}
  </a>

  <span
    v-else-if="text"
    class="block text-n-slate-12"
    :class="wrap ? 'break-words' : 'truncate'"
    :title="wrap ? undefined : String(text)"
  >
    {{ text }}
  </span>

  <span v-else-if="belezakiHint" class="text-xs text-n-slate-10">
    {{ belezakiHint }}
  </span>

  <span v-else class="text-n-slate-8">—</span>
</template>
