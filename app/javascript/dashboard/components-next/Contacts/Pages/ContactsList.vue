<script setup>
import { ref, computed } from 'vue';
import { useRouter, useRoute } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useContactsView } from 'dashboard/composables/useContactsView';
import { useBelezakiSummaries } from 'dashboard/composables/useBelezakiSummaries';
import {
  BELEZAKI_FIELDS,
  STANDARD_FIELDS,
  customFields,
} from 'dashboard/components-next/Contacts/helper/contactFields';
import ContactsTable from 'dashboard/components-next/Contacts/ContactsView/ContactsTable.vue';
import ContactsGrid from 'dashboard/components-next/Contacts/ContactsView/ContactsGrid.vue';
import ContactPreviewPanel from 'dashboard/components-next/Contacts/ContactsView/ContactPreviewPanel.vue';

const props = defineProps({
  contacts: { type: Array, required: true },
  selectedContactIds: {
    type: Array,
    default: () => [],
  },
  activeSort: { type: String, default: '' },
  activeOrdering: { type: String, default: '' },
});

const emit = defineEmits(['toggleContact', 'toggleAll', 'sort']);

const router = useRouter();
const route = useRoute();

const labels = useMapGetter('labels/getLabels');
const contactAttributes = useMapGetter('attributes/getContactAttributes');
const { viewMode, belezakiAvailable, belezakiEnabled, isFieldVisible } =
  useContactsView();

const selectedIds = computed(() => new Set(props.selectedContactIds));
const labelColors = computed(() =>
  Object.fromEntries(labels.value.map(({ title, color }) => [title, color]))
);

const contactFields = computed(() => [
  ...STANDARD_FIELDS,
  ...customFields(contactAttributes.value),
]);
const visibleFields = computed(() =>
  [...BELEZAKI_FIELDS, ...contactFields.value].filter(isFieldVisible)
);

const contactIds = computed(() => props.contacts.map(({ id }) => id));
const { summaries } = useBelezakiSummaries(contactIds, belezakiEnabled);

const previewId = ref(null);
const previewContact = computed(() =>
  props.contacts.find(({ id }) => id === previewId.value)
);

const openPreview = ({ id }) => {
  previewId.value = id;
};

const showDetails = async id => {
  const routeTypes = {
    contacts_dashboard_segments_index: ['contacts_edit_segment', 'segmentId'],
    contacts_dashboard_labels_index: ['contacts_edit_label', 'label'],
  };
  const [name, paramKey] = routeTypes[route.name] || ['contacts_edit'];
  const params = {
    contactId: id,
    ...(paramKey && { [paramKey]: route.params[paramKey] }),
  };

  await router.push({ name, params, query: route.query });
};
</script>

<template>
  <ContactsTable
    v-if="viewMode === 'list'"
    :contacts="contacts"
    :fields="visibleFields"
    :selected-ids="selectedIds"
    :label-colors="labelColors"
    :summaries="summaries"
    :active-sort="activeSort"
    :active-ordering="activeOrdering"
    @open="openPreview"
    @select="emit('toggleContact', $event)"
    @select-all="emit('toggleAll', $event)"
    @sort="emit('sort', $event)"
  />
  <ContactsGrid
    v-else
    :contacts="contacts"
    :fields="visibleFields"
    :selected-ids="selectedIds"
    :label-colors="labelColors"
    :summaries="summaries"
    @open="openPreview"
    @select="emit('toggleContact', $event)"
  />
  <ContactPreviewPanel
    v-if="previewContact"
    :contact="previewContact"
    :fields="contactFields"
    :label-colors="labelColors"
    :show-belezaki="belezakiAvailable"
    @close="previewId = null"
    @show-details="showDetails"
  />
</template>
