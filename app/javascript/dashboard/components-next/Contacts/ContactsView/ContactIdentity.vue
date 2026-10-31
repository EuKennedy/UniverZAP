<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import {
  contactPhone,
  contactTitle,
  hasRawName,
} from '../helper/contactFields';

const props = defineProps({
  contact: { type: Object, required: true },
  size: { type: Number, default: 32 },
  // Second line, for layouts without a phone column.
  showPhone: { type: Boolean, default: false },
});

const { t } = useI18n();

const title = computed(
  () =>
    contactTitle(props.contact) || t('CONTACTS_LAYOUT.FIELDS.WITHOUT_NUMBER')
);
const subtitle = computed(() => {
  const phone = contactPhone(props.contact);
  return props.showPhone && phone !== title.value ? phone : '';
});
</script>

<template>
  <span class="flex items-center min-w-0 gap-2.5">
    <Avatar
      :name="hasRawName(contact) ? '' : title"
      :src="contact.thumbnail"
      :size="size"
      :status="contact.availabilityStatus"
      hide-offline-status
      rounded-full
    />
    <span class="min-w-0">
      <span class="block text-sm font-medium truncate text-n-slate-12">
        {{ title }}
      </span>
      <span v-if="subtitle" class="block text-xs truncate text-n-slate-11">
        {{ subtitle }}
      </span>
    </span>
  </span>
</template>
