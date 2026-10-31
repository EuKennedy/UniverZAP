<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useContactsView } from 'dashboard/composables/useContactsView';
import {
  BELEZAKI_FIELDS,
  STANDARD_FIELDS,
  customFields,
} from '../helper/contactFields';
import { useContactFieldLabel } from './useContactFieldLabel';
import ContactsToolbarMenu from './ContactsToolbarMenu.vue';

const { t } = useI18n();
const fieldLabel = useContactFieldLabel();

const contactAttributes = useMapGetter('attributes/getContactAttributes');
const {
  viewMode,
  isPhone,
  belezakiAvailable,
  belezakiEnabled,
  isFieldVisible,
  toggleField,
  setViewMode,
  setBelezakiEnabled,
  showAllFields,
} = useContactsView();

const groups = computed(() =>
  [
    { key: 'STANDARD', fields: STANDARD_FIELDS },
    { key: 'CUSTOM', fields: customFields(contactAttributes.value) },
    belezakiEnabled.value && { key: 'BELEZAKI', fields: BELEZAKI_FIELDS },
  ].filter(group => group && group.fields.length)
);

const modes = [
  { key: 'list', icon: 'i-lucide-rows-3' },
  { key: 'cards', icon: 'i-lucide-layout-grid' },
];
</script>

<template>
  <button
    v-if="belezakiAvailable"
    type="button"
    class="inline-flex items-center flex-shrink-0 h-8 gap-1.5 px-2.5 text-xs font-medium transition rounded-lg outline outline-1 -outline-offset-1"
    :class="
      belezakiEnabled
        ? 'bg-brand-gradient-soft text-n-teal-11 outline-n-teal-7'
        : 'bg-n-solid-2 text-n-slate-11 outline-n-weak hover:text-n-slate-12 hover:outline-n-strong'
    "
    :title="t('CONTACTS_LAYOUT.VIEW.BELEZAKI_HINT')"
    :aria-pressed="belezakiEnabled"
    @click="setBelezakiEnabled(!belezakiEnabled)"
  >
    <span class="i-lucide-sparkles size-3.5" />
    {{ t('CONTACTS_LAYOUT.VIEW.BELEZAKI') }}
  </button>

  <ContactsToolbarMenu
    icon="i-lucide-columns-3"
    :label="t('CONTACTS_LAYOUT.VIEW.FIELDS')"
    align="end"
  >
    <div class="w-56">
      <template v-for="group in groups" :key="group.key">
        <p
          class="px-2 pt-2 pb-1 text-[11px] font-semibold tracking-wide uppercase text-n-slate-10"
        >
          {{ t(`CONTACTS_LAYOUT.VIEW.GROUPS.${group.key}`) }}
        </p>
        <label
          v-for="field in group.fields"
          :key="field.key"
          class="flex items-center gap-2 px-2 py-1.5 text-sm rounded-lg cursor-pointer text-n-slate-12 hover:bg-n-alpha-2"
        >
          <Checkbox
            :model-value="isFieldVisible(field)"
            @change="toggleField(field)"
          />
          <span class="truncate">{{ fieldLabel(field) }}</span>
        </label>
      </template>
      <button
        type="button"
        class="w-full px-2 py-1.5 mt-1 text-xs font-medium text-start border-t border-n-weak text-n-slate-11 hover:text-n-slate-12"
        @click="showAllFields"
      >
        {{ t('CONTACTS_LAYOUT.VIEW.SHOW_ALL') }}
      </button>
    </div>
  </ContactsToolbarMenu>

  <div
    v-if="!isPhone"
    class="flex items-center flex-shrink-0 h-8 p-0.5 rounded-lg outline outline-1 -outline-offset-1 outline-n-weak bg-n-solid-2"
    role="group"
    :aria-label="t('CONTACTS_LAYOUT.VIEW.MODE')"
  >
    <button
      v-for="mode in modes"
      :key="mode.key"
      type="button"
      class="inline-flex items-center justify-center h-full gap-1.5 px-2 text-xs font-medium transition rounded-md"
      :class="
        viewMode === mode.key
          ? 'bg-brand-gradient-soft text-n-teal-11'
          : 'text-n-slate-11 hover:text-n-slate-12'
      "
      :aria-pressed="viewMode === mode.key"
      @click="setViewMode(mode.key)"
    >
      <span class="size-3.5" :class="mode.icon" />
      {{ t(`CONTACTS_LAYOUT.VIEW.${mode.key.toUpperCase()}`) }}
    </button>
  </div>
</template>
