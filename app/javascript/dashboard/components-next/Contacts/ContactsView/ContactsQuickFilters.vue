<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import {
  PERIOD_DAYS,
  quickFilterState,
  withQuickFilter,
} from '../helper/quickFilters';
import ContactsToolbarMenu from './ContactsToolbarMenu.vue';

const emit = defineEmits(['change', 'clear']);

const { t } = useI18n();

const appliedFilters = useMapGetter('contacts/getAppliedContactFilters');
const labels = useMapGetter('labels/getLabels');
const contactAttributes = useMapGetter('attributes/getContactAttributes');

const hasAttribute = key =>
  contactAttributes.value.some(({ attributeKey }) => attributeKey === key);

const state = computed(() => quickFilterState(appliedFilters.value));

const originOptions = [
  { id: 'anuncio_facebook', name: t('CONTACTS_LAYOUT.FIELDS.ORIGIN_AD') },
  { id: 'organico', name: t('CONTACTS_LAYOUT.FIELDS.ORIGIN_ORGANIC') },
];
const typeOptions = [
  { id: 'new', name: t('CONTACTS_LAYOUT.FIELDS.TYPE_NEW') },
  { id: 'recurring', name: t('CONTACTS_LAYOUT.FIELDS.TYPE_RECURRING') },
];
const phoneOptions = [
  { id: 'with', name: t('CONTACTS_LAYOUT.QUICK_FILTERS.WITH_PHONE') },
  { id: 'without', name: t('CONTACTS_LAYOUT.QUICK_FILTERS.WITHOUT_PHONE') },
];
const periodOptions = PERIOD_DAYS.map(days => ({
  id: days,
  name: t('CONTACTS_LAYOUT.QUICK_FILTERS.LAST_DAYS', { days }),
}));

// The chips that only exist once the account has the attribute: a filter on a
// missing definition is refused by the server.
const menus = computed(() =>
  [
    hasAttribute('origem_lead') && {
      name: 'origin',
      icon: 'i-lucide-megaphone',
      label: t('CONTACTS_LAYOUT.QUICK_FILTERS.ORIGIN'),
      options: originOptions,
    },
    hasAttribute('recorrente') && {
      name: 'type',
      icon: 'i-lucide-repeat',
      label: t('CONTACTS_LAYOUT.QUICK_FILTERS.TYPE'),
      options: typeOptions,
    },
    {
      name: 'period',
      icon: 'i-lucide-calendar',
      label: t('CONTACTS_LAYOUT.QUICK_FILTERS.PERIOD'),
      options: periodOptions,
    },
    {
      name: 'phone',
      icon: 'i-lucide-phone',
      label: t('CONTACTS_LAYOUT.QUICK_FILTERS.PHONE'),
      options: phoneOptions,
    },
  ].filter(Boolean)
);

const change = (name, value) =>
  emit('change', withQuickFilter(appliedFilters.value, name, value));

const selectedName = menu =>
  menu.options.find(option => option.id === state.value[menu.name])?.name || '';

const selectedLabels = computed(() => state.value.labels.map(item => item.id));
const labelsSummary = computed(() => {
  const [first, ...others] = selectedLabels.value;
  if (!first) return '';
  return others.length ? `${first} +${others.length}` : first;
});

const toggleLabel = title => {
  const selected = selectedLabels.value;
  change(
    'labels',
    selected.includes(title)
      ? selected.filter(item => item !== title)
      : [...selected, title]
  );
};
</script>

<template>
  <ContactsToolbarMenu
    icon="i-lucide-tag"
    :label="t('CONTACTS_LAYOUT.QUICK_FILTERS.LABELS')"
    :value="labelsSummary"
    @clear="change('labels', [])"
  >
    <button
      v-for="label in labels"
      :key="label.id"
      type="button"
      class="flex items-center w-full gap-2 px-2 py-1.5 text-sm rounded-lg text-n-slate-12 hover:bg-n-alpha-2"
      @click="toggleLabel(label.title)"
    >
      <span
        class="flex-shrink-0 rounded-sm size-2.5"
        :style="{ backgroundColor: label.color }"
      />
      <span class="flex-1 truncate text-start">{{ label.title }}</span>
      <span
        v-if="selectedLabels.includes(label.title)"
        class="i-lucide-check size-4 text-n-teal-11"
      />
    </button>
  </ContactsToolbarMenu>

  <ContactsToolbarMenu
    v-for="menu in menus"
    :key="menu.name"
    :icon="menu.icon"
    :label="menu.label"
    :value="selectedName(menu)"
    @clear="change(menu.name, null)"
  >
    <template #default="{ close }">
      <button
        v-for="option in menu.options"
        :key="option.id"
        type="button"
        class="flex items-center justify-between w-full gap-2 px-2 py-1.5 text-sm rounded-lg text-n-slate-12 hover:bg-n-alpha-2"
        @click="
          change(menu.name, option.id);
          close();
        "
      >
        {{ option.name }}
        <span
          v-if="state[menu.name] === option.id"
          class="i-lucide-check size-4 text-n-teal-11"
        />
      </button>
    </template>
  </ContactsToolbarMenu>

  <button
    v-if="appliedFilters.length"
    type="button"
    class="h-8 px-1 text-xs font-medium text-n-slate-11 hover:text-n-slate-12"
    @click="emit('clear')"
  >
    {{ t('CONTACTS_LAYOUT.FILTER.ACTIVE_FILTERS.CLEAR_FILTERS') }}
  </button>
</template>
